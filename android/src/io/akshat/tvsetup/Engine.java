package io.akshat.tvsetup;

import android.content.Context;
import android.content.pm.*;
import android.os.Build;
import android.util.Base64;
import com.cgutman.adblib.*;
import java.io.*;
import java.net.*;
import java.security.MessageDigest;
import java.util.*;

final class Engine implements Closeable {
    private final Context context;
    private volatile LegacyClient client;
    private volatile boolean cancelled;
    Engine(Context context){this.context=context.getApplicationContext();}
    Catalog.TV connect(String host,int port,Catalog catalog)throws Exception {
        if(cancelled||Thread.currentThread().isInterrupted())throw new InterruptedIOException("Cancelled");
        File directory=new File(context.getNoBackupFilesDir(),"adb");
        if(!directory.isDirectory()&&!directory.mkdirs())throw new IOException("Cannot create private phone identity storage");
        File privateKey=new File(directory,"identity.key"),publicKey=new File(directory,"identity.pub");
        AdbBase64 base64=data->Base64.encodeToString(data,Base64.NO_WRAP);
        AdbCrypto crypto;
        // Never silently replace a damaged identity. Revocation is a TV user action.
        if(privateKey.exists()||publicKey.exists())crypto=AdbCrypto.loadAdbKeyPair(base64,privateKey,publicKey);
        else {crypto=AdbCrypto.generateAdbKeyPair(base64);crypto.saveAdbKeyPair(privateKey,publicKey);}
        LegacyClient session=new LegacyClient(crypto);client=session;
        if(cancelled||Thread.currentThread().isInterrupted()){session.close();throw new InterruptedIOException("Cancelled");}
        session.connect(host,port);
        if(!session.owner().equals("0"))throw new IOException("Use the TV's owner profile for this preview");
        Catalog.TV tv=new Catalog.TV();
        String model=session.model();tv.model=model.substring(0,Math.min(model.length(),120));
        tv.sdk=session.sdk();tv.abis.addAll(Arrays.asList(session.abis()));tv.isTV=session.isTV();
        Set<String> packages=new HashSet<>();for(Catalog.Feature f:catalog.features)for(Catalog.Artifact a:f.artifacts)packages.add(a.pkg);
        for(String pkg:packages)if(session.installed(pkg))tv.installed.add(pkg);
        return tv;
    }
    String install(Catalog.Artifact artifact)throws Exception {
        LegacyClient session=client;if(session==null)throw new IOException("Reconnect before installing");
        if(session.installed(artifact.pkg))return "Kept existing app unchanged";
        File apk=download(artifact);
        try {
            verify(apk,artifact);
            if(session.installed(artifact.pkg))return "Kept existing app unchanged";
            String result=session.install(apk,artifact.size);
            boolean success=false;for(String line:result.split("\n"))if(line.trim().equals("Success"))success=true;
            if(!success||!session.installed(artifact.pkg))throw new IOException("Installation did not report success. Reconnect to check the TV; no existing app was replaced.");
            return "Installed and confirmed";
        } finally {apk.delete();}
    }
    private File download(Catalog.Artifact artifact)throws Exception {
        File file=File.createTempFile("verified-", ".apk",context.getCacheDir());
        try {
            InputStream input;
            HttpURLConnection active=null;
            if(artifact.url.equals("bundled:search-handoff-1.0.apk"))input=context.getAssets().open("search-handoff-1.0.apk");
            else {
                URL url=new URL(artifact.url);int redirects=0;
                while(true) {
                    if(!url.getProtocol().equals("https")||!Arrays.asList("github.com","release-assets.githubusercontent.com","objects.githubusercontent.com").contains(url.getHost()))throw new IOException("Download redirected outside trusted HTTPS hosts");
                    active=(HttpURLConnection)url.openConnection();active.setInstanceFollowRedirects(false);
                    active.setConnectTimeout(15000);active.setReadTimeout(30000);
                    int status=active.getResponseCode();
                    if(status==301||status==302||status==303||status==307||status==308) {
                        String location=active.getHeaderField("Location");active.disconnect();
                        if(location==null||++redirects>5)throw new IOException("Too many publisher redirects");
                        url=new URL(url,location);continue;
                    }
                    if(status!=200){active.disconnect();throw new IOException("Publisher download is unavailable");}
                    long size=active.getContentLengthLong();
                    if(size!=-1&&size!=artifact.size){active.disconnect();throw new IOException("Publisher release size changed");}
                    input=active.getInputStream();break;
                }
            }
            try(InputStream source=input;OutputStream output=new FileOutputStream(file)) {
                byte[] buffer=new byte[65536];int count,total=0;
                while((count=source.read(buffer))!=-1) {
                    if(Thread.currentThread().isInterrupted())throw new InterruptedIOException("Cancelled");
                    total+=count;if(total>artifact.size)throw new IOException("Download exceeds pinned size");
                    output.write(buffer,0,count);
                }
            } finally {if(active!=null)active.disconnect();}
            verify(file,artifact);return file;
        } catch(Exception error){file.delete();throw error;}
    }
    @SuppressWarnings("deprecation") private void verify(File file,Catalog.Artifact artifact)throws Exception {
        if(file.length()!=artifact.size)throw new IOException("Incomplete download");
        MessageDigest digest=MessageDigest.getInstance("SHA-256");
        try(InputStream input=new FileInputStream(file)){byte[] buffer=new byte[65536];int n;while((n=input.read(buffer))!=-1)digest.update(buffer,0,n);}
        if(!hex(digest.digest()).equals(artifact.sha256))throw new IOException("Download does not match pinned SHA256. Nothing installed.");
        int flags=Build.VERSION.SDK_INT>=28?PackageManager.GET_SIGNING_CERTIFICATES:PackageManager.GET_SIGNATURES;
        PackageInfo info=context.getPackageManager().getPackageArchiveInfo(file.getAbsolutePath(),flags);
        if(info==null||!artifact.pkg.equals(info.packageName)||!artifact.version.equals(info.versionName))throw new IOException("Unexpected APK package or version");
        Signature[] signatures=Build.VERSION.SDK_INT>=28?(info.signingInfo==null?null:info.signingInfo.getApkContentsSigners()):info.signatures;
        if(signatures==null||signatures.length!=1||!hex(MessageDigest.getInstance("SHA-256").digest(signatures[0].toByteArray())).equals(artifact.signer))throw new IOException("APK certificate differs from pinned publisher");
    }
    static String hex(byte[] data){StringBuilder result=new StringBuilder();for(byte b:data)result.append(String.format(Locale.ROOT,"%02x",b&255));return result.toString();}
    public void close(){cancelled=true;LegacyClient current=client;client=null;if(current!=null)current.close();}
}
