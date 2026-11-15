package com.cgutman.adblib;

import java.io.*;
import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

public final class LegacyClientTest {
    private static int checks;
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    private interface Action{void run()throws Exception;}
    private static void rejects(Action action)throws Exception{checks++;try{action.run();throw new AssertionError("Expected rejection");}catch(IOException expected){}}
    private static byte[] message(int command,int a,int b,byte[] payload){return AdbProtocol.generateMessage(command,a,b,payload);}
    private static byte[] join(byte[]... chunks)throws IOException{ByteArrayOutputStream out=new ByteArrayOutputStream();for(byte[] c:chunks)out.write(c);return out.toByteArray();}
    private static byte[] text(String value){return value.getBytes(StandardCharsets.UTF_8);}
    private static byte[] cnxn(){return message(AdbProtocol.CMD_CNXN,AdbProtocol.CONNECT_VERSION,1024,null);}
    private static byte[] response(int id,String value)throws Exception{return join(message(AdbProtocol.CMD_OKAY,100+id,id,null),message(AdbProtocol.CMD_WRTE,100+id,id,text(value)),message(AdbProtocol.CMD_CLSE,100+id,id,null));}
    private static List<AdbProtocol.AdbMessage> decode(byte[] bytes)throws Exception{List<AdbProtocol.AdbMessage> result=new ArrayList<>();ByteArrayInputStream input=new ByteArrayInputStream(bytes);while(input.available()>0)result.add(AdbProtocol.AdbMessage.parseAdbMessage(input));return result;}
    public static void main(String[] args)throws Exception{
        AdbCrypto crypto=AdbCrypto.generateAdbKeyPair(data->Base64.getEncoder().encodeToString(data));
        for(String host:new String[]{"10.8.7.6","172.16.0.1","172.31.255.254","192.168.8.7"})check(LegacyClient.privateAddress(host).equals(host),"private endpoint");
        for(String host:new String[]{"8.8.8.8","127.0.0.1","0.0.0.0","169.254.1.1","172.32.0.1","tv.local","10.0.0.999","10.8.7.6;reboot","::1"})rejects(()->LegacyClient.privateAddress(host));
        byte[] valid=message(AdbProtocol.CMD_WRTE,2,3,text("hello"));
        check(AdbProtocol.validateMessage(AdbProtocol.AdbMessage.parseAdbMessage(new ByteArrayInputStream(valid))),"valid packet");
        for(int n=0;n<valid.length;n++){final byte[] truncated=Arrays.copyOf(valid,n);rejects(()->AdbProtocol.AdbMessage.parseAdbMessage(new ByteArrayInputStream(truncated)));}
        for(int length:new int[]{-1,262145,Integer.MAX_VALUE}){
            byte[] bad=valid.clone();ByteBuffer.wrap(bad).order(ByteOrder.LITTLE_ENDIAN).putInt(12,length);
            rejects(()->AdbProtocol.AdbMessage.parseAdbMessage(new ByteArrayInputStream(bad)));
        }
        byte[] badMagic=valid.clone();badMagic[20]^=1;rejects(()->AdbProtocol.AdbMessage.parseAdbMessage(new ByteArrayInputStream(badMagic)));
        byte[] badChecksum=valid.clone();badChecksum[24]^=1;check(!AdbProtocol.validateMessage(AdbProtocol.AdbMessage.parseAdbMessage(new ByteArrayInputStream(badChecksum))),"checksum refusal");
        byte[] token=new byte[20];Arrays.fill(token,(byte)4);
        ByteArrayOutputStream sent=new ByteArrayOutputStream();
        LegacyClient auth=new LegacyClient(crypto,new ByteArrayInputStream(join(message(AdbProtocol.CMD_AUTH,1,0,token),message(AdbProtocol.CMD_AUTH,1,0,token),cnxn())),sent);
        auth.handshake();List<AdbProtocol.AdbMessage> authPackets=decode(sent.toByteArray());
        check(authPackets.size()==3,"auth packet count");check(authPackets.get(1).arg0==2&&authPackets.get(2).arg0==3,"sign then authorize");
        check(Arrays.equals(authPackets.get(1).payload,crypto.signAdbTokenPayload(token)),"correct signature");
        LegacyClient tls=new LegacyClient(crypto,new ByteArrayInputStream(message(0x534c5453,0,0,null)),new ByteArrayOutputStream());rejects(tls::handshake);
        sent=new ByteArrayOutputStream();LegacyClient probe=new LegacyClient(crypto,new ByteArrayInputStream(join(cnxn(),response(1,"Example TV\n"),response(2,"30\n"),response(3,"armeabi-v7a\n"),response(4,"feature:android.software.leanback\n"),response(5,"package:ch.protonvpn.android\n"))),sent);
        probe.handshake();check(probe.model().equals("Example TV"),"model read");check(probe.sdk()==30,"sdk read");check(probe.abis()[0].equals("armeabi-v7a"),"abi read");check(probe.isTV(),"TV guard");check(probe.installed("ch.protonvpn.android"),"exact package detection");
        List<String> commands=new ArrayList<>();for(AdbProtocol.AdbMessage p:decode(sent.toByteArray()))if(p.command==AdbProtocol.CMD_OPEN)commands.add(new String(p.payload,StandardCharsets.UTF_8));
        check(commands.size()==5,"bounded probe commands");check(commands.stream().allMatch(v->v.startsWith("shell:getprop ")||v.startsWith("shell:pm list ")),"read-only probe");
        rejects(()->probe.installed("a.b;reboot"));
        File apk=File.createTempFile("tv-setup-test-", ".apk");
        try{
            byte[] bytes=new byte[5123];new Random(42).nextBytes(bytes);try(OutputStream out=new FileOutputStream(apk)){out.write(bytes);}
            ByteArrayOutputStream replies=new ByteArrayOutputStream();replies.write(cnxn());replies.write(message(AdbProtocol.CMD_OKAY,101,1,null));
            for(int n=0;n<(bytes.length+1023)/1024;n++)replies.write(message(AdbProtocol.CMD_OKAY,101,1,null));
            replies.write(message(AdbProtocol.CMD_WRTE,101,1,text("Success\n")));replies.write(message(AdbProtocol.CMD_CLSE,101,1,null));
            sent=new ByteArrayOutputStream();LegacyClient install=new LegacyClient(crypto,new ByteArrayInputStream(replies.toByteArray()),sent);install.handshake();
            check(install.install(apk,bytes.length).trim().equals("Success"),"install response");
            ByteArrayOutputStream uploaded=new ByteArrayOutputStream();
            for(AdbProtocol.AdbMessage p:decode(sent.toByteArray())){
                if(p.command==AdbProtocol.CMD_WRTE){check(p.payload.length<=1024,"peer maximum respected");uploaded.write(p.payload);}
                if(p.command==AdbProtocol.CMD_OPEN)check(new String(p.payload,StandardCharsets.UTF_8).equals("exec:cmd package install --user 0 -S "+bytes.length+"\0"),"no reinstall/update flags");
            }
            check(Arrays.equals(uploaded.toByteArray(),bytes),"all APK bytes delivered in order");
        }finally{apk.delete();}
        LegacyClient mismatch=new LegacyClient(crypto,new ByteArrayInputStream(join(cnxn(),message(AdbProtocol.CMD_OKAY,101,99,null))),new ByteArrayOutputStream());mismatch.handshake();rejects(mismatch::model);
        LegacyClient oversized=new LegacyClient(crypto,new ByteArrayInputStream(join(cnxn(),response(1,new String(new char[65537]).replace('\0','x')))),new ByteArrayOutputStream());oversized.handshake();rejects(oversized::model);
        LegacyClient closed=new LegacyClient(crypto);closed.close();rejects(()->closed.connect("10.8.7.6",5555));
        System.out.println("Java ADB safety tests: "+checks+" checks passed; fake streams only, no network or TV.");
    }
}
