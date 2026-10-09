package com.klee.rebootubuntu;

import android.app.Activity;
import android.app.AlertDialog;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.BufferedReader;
import java.io.InputStreamReader;

/**
 * klee dual boot: switch to Ubuntu Touch. The root script
 * /data/adb/klee/klee-request-switch.sh leaves a job for OrangeFox and reboots
 * to recovery, where the boot images can be written (Android keeps them write
 * protected); this activity only asks for confirmation and shows the output.
 */
public class MainActivity extends Activity {
    private static final String SCRIPT = "/data/adb/klee/klee-request-switch.sh";

    private final Handler ui = new Handler(Looper.getMainLooper());
    private TextView log;
    private Button go;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        int pad = (int) (24 * getResources().getDisplayMetrics().density);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(pad, pad * 3, pad, pad);
        root.setGravity(Gravity.CENTER_HORIZONTAL);

        TextView title = new TextView(this);
        title.setText("Ubuntu Touch");
        title.setTextSize(30);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        title.setGravity(Gravity.CENTER);
        root.addView(title);

        TextView info = new TextView(this);
        info.setText("Telefon OrangeFox'a yeniden başlar. Orada ekran kilidi PIN'ini gir, "
                + "Ubuntu Touch otomatik kurulup açılır.\n"
                + "Axion'a dönmek için Ubuntu'daki \"Android'e Geç\" uygulamasını kullan.");
        info.setGravity(Gravity.CENTER);
        info.setPadding(0, pad / 2, 0, pad);
        root.addView(info);

        go = new Button(this);
        go.setText("Ubuntu'ya geç");
        go.setTextSize(20);
        go.setBackgroundColor(Color.parseColor("#E95420"));
        go.setTextColor(Color.WHITE);
        go.setPadding(pad, pad / 2, pad, pad / 2);
        go.setOnClickListener(v -> confirm());
        root.addView(go);

        log = new TextView(this);
        log.setTypeface(Typeface.MONOSPACE);
        log.setPadding(0, pad, 0, 0);
        ScrollView scroll = new ScrollView(this);
        scroll.addView(log);
        root.addView(scroll, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f));

        setContentView(root);
    }

    private void confirm() {
        new AlertDialog.Builder(this)
                .setTitle("Ubuntu Touch'a geçilsin mi?")
                .setMessage("Telefon şimdi OrangeFox'a yeniden başlayacak. PIN'ini girmeyi unutma.")
                .setPositiveButton("Geç", (d, w) -> run())
                .setNegativeButton("Vazgeç", null)
                .show();
    }

    private void append(String line) {
        ui.post(() -> log.append(line + "\n"));
    }

    private void run() {
        go.setEnabled(false);
        log.setText("");
        new Thread(() -> {
            try {
                Process p = new ProcessBuilder("su", "-c", "sh " + SCRIPT + " ubuntu")
                        .redirectErrorStream(true).start();
                BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()));
                String line;
                while ((line = r.readLine()) != null) {
                    append(line);
                }
                int rc = p.waitFor();
                if (rc != 0) {
                    append("(çıkış kodu " + rc + ")");
                }
            } catch (Exception e) {
                append("HATA: root çalıştırılamadı: " + e.getMessage());
                append("KernelSU > Süper kullanıcı listesinden bu uygulamaya izin ver.");
            }
            ui.post(() -> go.setEnabled(true));
        }).start();
    }
}
