package io.akshat.tvsetup;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import org.json.*;

public final class CatalogTest {
    static int checks;
    interface Action{void run()throws Exception;}
    static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    static void rejects(Action action)throws Exception{checks++;try{action.run();throw new AssertionError("Expected rejection");}catch(IOException expected){}}
    static Catalog catalog(String json)throws Exception{return new Catalog(new ByteArrayInputStream(json.getBytes(StandardCharsets.UTF_8)));}
    public static void main(String[] args)throws Exception{
        String original=new String(java.nio.file.Files.readAllBytes(new File(args[0]).toPath()),StandardCharsets.UTF_8);
        Catalog catalog=catalog(original);check(catalog.features.size()==3,"feature count");
        Catalog.TV tv=new Catalog.TV();tv.model="Example TV";tv.sdk=30;tv.abis.add("armeabi-v7a");tv.isTV=true;
        Set<String> all=new HashSet<>(Arrays.asList("tizentube","voice","proton"));
        List<Catalog.Item> plan=catalog.plan(tv,all);
        check(plan.size()==3,"all opted-in features");check(plan.get(0).artifact.id.equals("tizentube-arm"),"32-bit build");
        tv.abis.add("arm64-v8a");check(catalog.plan(tv,all).get(0).artifact.id.equals("tizentube-arm64"),"64-bit build preferred");tv.abis.remove("arm64-v8a");
        rejects(()->catalog.plan(tv,new HashSet<>()));rejects(()->catalog.plan(tv,new HashSet<>(Arrays.asList("unknown"))));rejects(()->catalog.plan(tv,new HashSet<>(Arrays.asList("voice"))));
        tv.sdk=24;rejects(()->catalog.plan(tv,all));tv.sdk=30;
        tv.isTV=false;rejects(()->catalog.plan(tv,all));tv.isTV=true;
        tv.abis.clear();tv.abis.add("x86");rejects(()->catalog.plan(tv,all));tv.abis.clear();tv.abis.add("armeabi-v7a");
        for(Catalog.Feature f:catalog.features)for(Catalog.Artifact a:f.artifacts)tv.installed.add(a.pkg);
        check(catalog.plan(tv,all).stream().allMatch(item->item.artifact==null),"all pre-existing packages preserved");
        for(String[] replacement:new String[][]{{"url","http://github.com/a/b/releases/download/v1/a.apk"},{"url","https://example.com/a.apk"},{"url","https://github.com/a/b/releases/download/latest/a.apk"},{"url","bundled:private.apk"},{"package","a.b;reboot"},{"sha256","invalid"}}){
            JSONObject changed=new JSONObject(original);changed.getJSONArray("features").getJSONObject(0).getJSONArray("artifacts").getJSONObject(0).put(replacement[0],replacement[1]);
            rejects(()->catalog(changed.toString()));
        }
        System.out.println("Java catalog/planner tests: "+checks+" checks passed; no Android device or network.");
    }
}
