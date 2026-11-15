package io.akshat.tvsetup;

import org.json.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

final class Catalog {
    static final class Artifact {
        final String id,pkg,version,sha256,signer,url,source;
        final int minSdk,size;
        final Set<String> abis;
        Artifact(JSONObject json)throws Exception {
            id=json.getString("id");pkg=json.getString("package");version=json.getString("version");
            sha256=json.getString("sha256");signer=json.getString("signerSha256");url=json.getString("url");source=json.getString("source");
            minSdk=json.getInt("minSdk");size=json.getInt("size");abis=strings(json.getJSONArray("abis"));
            if(!pkg.matches("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+") || !sha256.matches("[a-f0-9]{64}") || !signer.matches("[a-f0-9]{64}") || minSdk<24 || minSdk>100 || size<1 || size>200000000)throw new IOException("Invalid artifact metadata");
            boolean release=url.matches("https://github\\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/releases/download/(?!latest/|main/|master/)[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\\.apk");
            if(!release && !url.equals("bundled:search-handoff-1.0.apk"))throw new IOException("Only pinned publisher downloads are allowed");
            if(!source.startsWith("https://github.com/"))throw new IOException("Invalid source URL");
        }
    }
    static final class Feature {
        final String id,name,description,manual;
        final Set<String> requires;
        final List<Artifact> artifacts=new ArrayList<>();
        Feature(JSONObject json)throws Exception {
            id=json.getString("id");name=json.getString("name");description=json.getString("description");manual=json.getString("manual");
            requires=json.has("requires")?strings(json.getJSONArray("requires")):Collections.emptySet();
            JSONArray array=json.getJSONArray("artifacts");
            for(int i=0;i<array.length();i++)artifacts.add(new Artifact(array.getJSONObject(i)));
            if(artifacts.isEmpty())throw new IOException("Missing artifacts");
        }
    }
    static final class TV {
        String model;int sdk;Set<String> abis=new HashSet<>(),installed=new HashSet<>();boolean isTV;
    }
    static final class Item {
        final Feature feature;final Artifact artifact;
        Item(Feature feature,Artifact artifact){this.feature=feature;this.artifact=artifact;}
        String status(){return artifact==null?"Keep existing app unchanged":"Install "+artifact.version+" ("+(artifact.size/1000000)+" MB)";}
    }
    final List<Feature> features=new ArrayList<>();
    Catalog(InputStream resource)throws Exception {
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();
        try(InputStream input=resource){byte[] b=new byte[8192];int n;while((n=input.read(b))!=-1){if(bytes.size()+n>100000)throw new IOException("Catalog too large");bytes.write(b,0,n);}}
        JSONObject json=new JSONObject(new String(bytes.toByteArray(),StandardCharsets.UTF_8));
        if(json.getInt("schema")!=1)throw new IOException("Unsupported catalog schema");
        JSONArray array=json.getJSONArray("features");Set<String> ids=new HashSet<>(),artifacts=new HashSet<>();
        for(int i=0;i<array.length();i++){
            Feature f=new Feature(array.getJSONObject(i));if(!ids.add(f.id))throw new IOException("Duplicate feature");
            for(Artifact a:f.artifacts)if(!artifacts.add(a.id))throw new IOException("Duplicate artifact");
            features.add(f);
        }
        if(features.isEmpty())throw new IOException("Missing catalog");
        for(Feature f:features)if(!ids.containsAll(f.requires)||f.requires.contains(f.id))throw new IOException("Invalid dependencies");
    }
    List<Item> plan(TV tv,Set<String> selected)throws IOException {
        if(!tv.isTV)throw new IOException("This device does not report Android TV support. Nothing will be installed.");
        Set<String> known=new HashSet<>();for(Feature f:features)known.add(f.id);
        if(selected.isEmpty()||!known.containsAll(selected))throw new IOException("Choose at least one supported feature");
        List<Item> result=new ArrayList<>();
        for(Feature f:features)if(selected.contains(f.id)) {
            if(!selected.containsAll(f.requires))throw new IOException(f.name+" requires TizenTube to be selected");
            boolean installed=false;for(Artifact a:f.artifacts)if(tv.installed.contains(a.pkg))installed=true;
            if(installed){result.add(new Item(f,null));continue;}
            Artifact found=null;
            for(Artifact a:f.artifacts)if(tv.sdk>=a.minSdk&&(a.abis.isEmpty()||!Collections.disjoint(a.abis,tv.abis))){found=a;break;}
            if(found==null)throw new IOException(f.name+" is not supported on this TV's Android version or CPU. Nothing installed.");
            result.add(new Item(f,found));
        }
        return result;
    }
    private static Set<String> strings(JSONArray a)throws JSONException {Set<String> result=new LinkedHashSet<>();for(int i=0;i<a.length();i++)result.add(a.getString(i));return result;}
}
