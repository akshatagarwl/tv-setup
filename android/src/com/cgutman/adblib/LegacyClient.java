package com.cgutman.adblib;

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

/** TV Setup's sequential, bounded adapter. Upstream supplies codec/RSA only. */
public final class LegacyClient implements Closeable {
    private volatile Socket socket;
    private InputStream input;
    private OutputStream output;
    private final AdbCrypto crypto;
    private int nextId, maxData = 4096;
    private boolean connected;
    private volatile boolean cancelled;
    public LegacyClient(AdbCrypto crypto) { this.crypto = crypto; }
    LegacyClient(AdbCrypto crypto, InputStream input, OutputStream output) { this.crypto = crypto; this.input = input; this.output = output; }
    public void connect(String host, int port) throws Exception {
        String normalized = privateAddress(host);
        if (port < 1 || port > 65535) throw new IOException("Invalid ADB port");
        if (cancelled || Thread.currentThread().isInterrupted()) throw new InterruptedIOException("Cancelled");
        Socket connection = new Socket(); socket = connection;
        if (cancelled || Thread.currentThread().isInterrupted()) { close(); throw new InterruptedIOException("Cancelled"); }
        connection.connect(new InetSocketAddress(normalized, port), 15000);
        connection.setSoTimeout(60000); connection.setTcpNoDelay(true);
        input = connection.getInputStream(); output = connection.getOutputStream();
        try { handshake(); } catch (Exception error) { close(); throw error; }
    }
    public static String privateAddress(String host) throws IOException {
        if (!host.matches("[0-9]{1,3}(\\.[0-9]{1,3}){3}")) throw new IOException("Enter the TV's private IPv4 address, not a hostname or public address");
        String[] parts = host.split("\\."); int[] p = new int[4];
        for (int i=0;i<4;i++) { p[i]=Integer.parseInt(parts[i]); if(p[i]>255)throw new IOException("Invalid IPv4 address"); }
        if (!(p[0]==10 || (p[0]==172 && p[1]>=16 && p[1]<=31) || (p[0]==192 && p[1]==168))) throw new IOException("Only private local-network addresses are supported");
        return p[0]+"."+p[1]+"."+p[2]+"."+p[3];
    }
    void handshake() throws Exception {
        send(AdbProtocol.generateMessage(AdbProtocol.CMD_CNXN, AdbProtocol.CONNECT_VERSION, 262144, AdbProtocol.CONNECT_PAYLOAD));
        boolean signed=false;
        for(int n=0;n<5;n++) {
            AdbProtocol.AdbMessage packet=receive();
            if(packet.command==AdbProtocol.CMD_CNXN) {
                if(packet.arg1<=0)throw new IOException("Invalid peer packet size");
                maxData=Math.min(packet.arg1,65536); connected=true; return;
            }
            if(packet.command!=AdbProtocol.CMD_AUTH || packet.arg0!=1 || packet.payload==null || packet.payload.length!=20)
                throw new IOException("This preview supports classic network ADB, not wireless pairing/TLS ports");
            send(AdbProtocol.generateAuth(signed?3:2, signed?crypto.getAdbPublicKeyPayload():crypto.signAdbTokenPayload(packet.payload)));
            signed=true;
        }
        throw new IOException("TV authorization was not completed");
    }
    public String owner() throws Exception { return shell("am get-current-user").trim(); }
    public String model() throws Exception { return shell("getprop ro.product.model").trim(); }
    public int sdk() throws Exception { return Integer.parseInt(shell("getprop ro.build.version.sdk").trim()); }
    public String[] abis() throws Exception { return shell("getprop ro.product.cpu.abilist").trim().split(","); }
    public boolean isTV() throws Exception { String f=shell("pm list features");return f.contains("feature:android.software.leanback")||f.contains("feature:android.hardware.type.television"); }
    public boolean installed(String pkg) throws Exception {
        if(!pkg.matches("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+"))throw new IOException("Invalid package name");
        for(String line:shell("pm list packages "+pkg).split("\n"))if(line.trim().equals("package:"+pkg))return true;
        return false;
    }
    public String install(File apk, int expectedSize) throws Exception {
        if(expectedSize<1 || expectedSize>200000000 || apk.length()!=expectedSize)throw new IOException("Invalid APK size");
        return stream("exec:cmd package install --user 0 -S "+expectedSize, apk);
    }
    private String shell(String command) throws Exception { return stream("shell:"+command,null); }
    private String stream(String destination, File apk) throws Exception {
        if(!connected)throw new IOException("Not connected");
        int local=++nextId;
        try {
            send(AdbProtocol.generateOpen(local,destination));
            AdbProtocol.AdbMessage opened=receive();
            if(opened.command!=AdbProtocol.CMD_OKAY || opened.arg1!=local)throw new IOException("TV rejected the operation");
            int remote=opened.arg0; ByteArrayOutputStream result=new ByteArrayOutputStream();
            if(apk!=null)try(InputStream bytes=new FileInputStream(apk)) {
                byte[] buffer=new byte[maxData]; int count;
                while((count=bytes.read(buffer))!=-1) {
                    if(Thread.currentThread().isInterrupted())throw new InterruptedIOException("Cancelled");
                    send(AdbProtocol.generateWrite(local,remote,Arrays.copyOf(buffer,count)));
                    while(true) {
                        AdbProtocol.AdbMessage reply=receive(); collect(reply,local,remote,result);
                        if(reply.command==AdbProtocol.CMD_OKAY)break;
                        if(reply.command!=AdbProtocol.CMD_WRTE)throw new IOException("TV ended installation before all APK bytes arrived");
                    }
                }
            }
            while(true) {
                AdbProtocol.AdbMessage reply=receive(); collect(reply,local,remote,result);
                if(reply.command==AdbProtocol.CMD_CLSE) {send(AdbProtocol.generateClose(local,remote));break;}
                if(reply.command!=AdbProtocol.CMD_WRTE && reply.command!=AdbProtocol.CMD_OKAY)throw new IOException("Unexpected TV response");
            }
            return new String(result.toByteArray(),StandardCharsets.UTF_8);
        } catch(Exception error) { close(); throw error; }
    }
    private void collect(AdbProtocol.AdbMessage packet,int local,int remote,ByteArrayOutputStream result) throws Exception {
        if(packet.arg1!=local || packet.arg0!=remote)throw new IOException("Mismatched ADB stream");
        if(packet.command==AdbProtocol.CMD_WRTE) {
            if(result.size()+packet.payloadLength>65536)throw new IOException("TV response exceeded limit");
            if(packet.payload!=null)result.write(packet.payload);
            send(AdbProtocol.generateReady(local,remote));
        }
    }
    private void send(byte[] packet)throws IOException { output.write(packet);output.flush(); }
    private AdbProtocol.AdbMessage receive()throws IOException {
        AdbProtocol.AdbMessage packet=AdbProtocol.AdbMessage.parseAdbMessage(input);
        if(!AdbProtocol.validateMessage(packet))throw new IOException("Invalid ADB checksum");
        return packet;
    }
    public void close() { cancelled=true;connected=false;Socket current=socket;if(current!=null)try{current.close();}catch(IOException ignored){} }
}
