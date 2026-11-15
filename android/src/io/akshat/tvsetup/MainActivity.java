package io.akshat.tvsetup;

import android.app.*;
import android.os.Bundle;
import android.graphics.Color;
import android.text.InputType;
import android.view.*;
import android.widget.*;
import java.util.*;
import java.util.concurrent.*;

public final class MainActivity extends Activity {
    private final ExecutorService executor=Executors.newSingleThreadExecutor();
    private final Set<String> selected=new HashSet<>();
    private final List<String> results=new ArrayList<>();
    private Catalog catalog;private Catalog.TV tv;private List<Catalog.Item> plan=new ArrayList<>();
    private Engine engine;private Future<?> worker;private boolean busy,approved;private int generation;
    private String status="Nothing is connected. Your TV will not change until you approve installation.";
    private String host="",port="5555";private LinearLayout content;private EditText address,portInput;
    private final int ink=Color.rgb(232,239,248),muted=Color.rgb(165,181,201),accent=Color.rgb(106,224,200);
    @Override public void onCreate(Bundle state){super.onCreate(state);try{catalog=new Catalog(getAssets().open("catalog.json"));}catch(Exception error){status="Invalid bundled catalog. Setup is disabled.";}render();}
    private int dp(int value){return (int)(getResources().getDisplayMetrics().density*value);}
    private void text(String value,int size,int color){TextView view=new TextView(this);view.setText(value);view.setTextSize(size);view.setTextColor(color);view.setPadding(0,dp(5),0,dp(8));content.addView(view);}
    private void heading(String text){text(text,20,accent);}
    private void button(String label,boolean enabled,Runnable action){Button view=new Button(this);view.setText(label);view.setEnabled(enabled);view.setOnClickListener(v->action.run());content.addView(view,new LinearLayout.LayoutParams(-1,-2));}
    private void render(){
        ScrollView scroll=new ScrollView(this);scroll.setFillViewport(true);
        content=new LinearLayout(this);content.setOrientation(LinearLayout.VERTICAL);content.setPadding(dp(22),dp(24),dp(22),dp(32));content.setBackgroundColor(Color.rgb(12,18,32));scroll.addView(content);setContentView(scroll);
        text("TV Setup",32,ink);text("A calmer TV, from your phone",18,accent);
        text("Preview build · classic network ADB only",13,muted);
        text("Use the same trusted Wi-Fi. Enable network debugging on the TV first. Pairing-code-only TVs are not supported yet. Connecting may show an authorization prompt on the TV.",15,ink);
        heading("1 · Connect and check");
        address=new EditText(this);address.setSingleLine(true);address.setHint("TV IPv4 address");address.setText(host);address.setTextColor(ink);address.setHintTextColor(muted);address.setInputType(InputType.TYPE_CLASS_PHONE);address.setEnabled(!busy&&tv==null);content.addView(address);
        portInput=new EditText(this);portInput.setSingleLine(true);portInput.setHint("ADB port");portInput.setText(port);portInput.setTextColor(ink);portInput.setInputType(InputType.TYPE_CLASS_NUMBER);portInput.setEnabled(!busy&&tv==null);content.addView(portInput);
        button("Connect and read compatibility",!busy&&tv==null&&catalog!=null,this::connect);
        if(tv!=null)text(tv.model+" · Android API "+tv.sdk+" · "+String.join(", ",tv.abis),14,muted);
        heading("2 · Choose what to install");
        if(catalog!=null)for(Catalog.Feature feature:catalog.features){
            CheckBox box=new CheckBox(this);box.setText(feature.name);box.setTextSize(18);box.setTextColor(ink);box.setChecked(selected.contains(feature.id));box.setEnabled(!busy);
            box.setOnCheckedChangeListener((v,checked)->{
                saveAddress();if(checked){selected.add(feature.id);selected.addAll(feature.requires);}else{selected.remove(feature.id);if(feature.id.equals("tizentube"))selected.remove("voice");}
                changed();render();
            });content.addView(box);text(feature.description,14,muted);
        }
        button("Preview changes",!busy&&tv!=null&&tv.isTV&&!selected.isEmpty(),()->{saveAddress();changed();try{plan=catalog.plan(tv,selected);status="Review every item. Existing apps, accounts and settings will be kept.";}catch(Exception error){status=error.getMessage();}render();});
        text("Private channel lists, launcher changes and automatic permission grants are not included in this preview.",13,muted);
        if(!plan.isEmpty()){
            heading("3 · Review and approve");
            for(Catalog.Item item:plan){
                text(item.feature.name+" — "+item.status(),16,ink);
                if(item.artifact!=null){text("Source: "+item.artifact.source,12,muted);text("SHA256: "+item.artifact.sha256,11,muted);}
            }
            CheckBox consent=new CheckBox(this);consent.setText("The TV is not in use. I approve installing the missing apps shown above.");consent.setTextColor(ink);consent.setChecked(approved);consent.setEnabled(!busy);consent.setOnCheckedChangeListener((v,checked)->{approved=checked;saveAddress();render();});content.addView(consent);
            button("Install approved apps",!busy&&approved,this::install);
            text("No factory reset, removal, replacement, automatic launch, accessibility changes or VPN connection. Keep this app open; leaving it cancels unfinished work.",13,muted);
        }
        heading("Status");if(busy)content.addView(new ProgressBar(this));text(status,16,ink);
        for(String result:results)text(result,14,accent);
        button("Disconnect / cancel",busy||tv!=null,()->disconnect("Disconnected. A partially completed installation may have finished; reconnect to check. Existing apps were not replaced."));
        if(!results.isEmpty()){heading("Finish on the TV, when ready");for(Catalog.Item item:plan)text(item.feature.name+": "+item.feature.manual,15,ink);heading("Undo");text("Only for apps marked Installed in this run: open TV Settings → Apps and disable the new app if supported. Disabling preserves its data. Uninstall only if you accept losing that app's local data. Leave apps marked kept unchanged alone.",14,muted);}
        button("Open-source licenses",!busy,this::licenses);
        heading("Private by design");text("No analytics or account credentials. Your ADB identity stays in this phone's private, non-backed-up storage. Downloads go directly to pinned publishers. This installer never reads TV app profiles or imports someone else's preferences.",13,muted);
    }
    private void licenses(){
        try(java.io.InputStream input=getAssets().open("NOTICES.txt")){
            java.io.ByteArrayOutputStream bytes=new java.io.ByteArrayOutputStream();byte[] buffer=new byte[8192];int n;
            while((n=input.read(buffer))!=-1)bytes.write(buffer,0,n);
            TextView text=new TextView(this);text.setText(new String(bytes.toByteArray(),java.nio.charset.StandardCharsets.UTF_8));text.setTextIsSelectable(true);text.setPadding(dp(20),dp(12),dp(20),dp(12));
            ScrollView scroll=new ScrollView(this);scroll.addView(text);
            new AlertDialog.Builder(this).setTitle("Open-source licenses").setView(scroll).setPositiveButton("Close",null).show();
        }catch(java.io.IOException error){Toast.makeText(this,"License resource is missing",Toast.LENGTH_LONG).show();}
    }
    private void saveAddress(){host=address.getText().toString().trim();port=portInput.getText().toString().trim();}
    private void changed(){plan=new ArrayList<>();approved=false;results.clear();}
    private void post(int attempt,Runnable action){runOnUiThread(()->{if(attempt==generation&&!isDestroyed()){action.run();render();}});}
    private void failed(int attempt,Engine session,Exception error){session.close();post(attempt,()->{busy=false;approved=false;tv=null;plan=new ArrayList<>();getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);status="Stopped: "+error.getMessage()+". Reconnect and preview again to check installed apps.";});}
    private void connect(){
        saveAddress();int number;
        try{com.cgutman.adblib.LegacyClient.privateAddress(host);number=Integer.parseInt(port);if(number<1||number>65535)throw new Exception();}catch(Exception error){status="Enter the TV's private IPv4 address and ADB port (usually 5555).";render();return;}
        changed();tv=null;busy=true;int attempt=++generation;
        if(engine!=null)engine.close();Engine session=new Engine(this);engine=session;
        final String destination=host;final int destinationPort=number;
        status="Connecting. Approve this phone's authorization prompt on the TV.";render();
        worker=executor.submit(()->{try{Catalog.TV info=session.connect(destination,destinationPort,catalog);post(attempt,()->{tv=info;busy=false;status=info.isTV?"Connected. Compatibility check finished; no apps or settings changed.":"This is not a supported Android TV. Installation is disabled.";});}catch(Exception error){failed(attempt,session,error);}});
    }
    private void install(){
        if(busy||!approved||plan.isEmpty()||engine==null)return;
        final List<Catalog.Item> approvedPlan=new ArrayList<>(plan);final Engine session=engine;final int attempt=generation;
        busy=true;results.clear();getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);render();
        worker=executor.submit(()->{try{
            for(Catalog.Item item:approvedPlan){
                if(Thread.currentThread().isInterrupted())throw new InterruptedException("Cancelled");
                if(item.artifact==null){post(attempt,()->results.add(item.feature.name+": kept unchanged"));continue;}
                post(attempt,()->status="Downloading, verifying and installing "+item.feature.name+". Keep this app open…");
                String result=session.install(item.artifact);post(attempt,()->{if(tv!=null)tv.installed.add(item.artifact.pkg);results.add(item.feature.name+": "+result);});
            }
            post(attempt,()->{busy=false;approved=false;getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);status="Finished. Complete the TV steps below when convenient. Installation does not mean sign-in, permissions or playback have been verified.";});
        }catch(Exception error){failed(attempt,session,error);}});
    }
    private void disconnect(String reason){generation++;if(engine!=null)engine.close();engine=null;if(worker!=null)worker.cancel(true);worker=null;busy=false;tv=null;changed();getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);status=reason;render();}
    @Override protected void onStop(){super.onStop();if(busy)disconnect("Stopped because this app left the foreground. An installation may have finished; reconnect to check.");}
    @Override protected void onDestroy(){generation++;if(engine!=null)engine.close();if(worker!=null)worker.cancel(true);executor.shutdownNow();super.onDestroy();}
}
