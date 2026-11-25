package top.zesun.berryfcm;

import android.content.Context;
import android.os.Build;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import androidx.annotation.NonNull;
import io.github.muntashirakon.adb.AbsAdbConnectionManager;
import io.github.muntashirakon.adb.AdbStream;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.KeyPairGenerator;
import java.security.KeyStore;
import java.security.PrivateKey;
import java.security.cert.Certificate;
import java.util.UUID;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;

/** AndroidKeyStore ADB identity; six-digit pairing codes never persist. */
final class AdbConnectionManager extends AbsAdbConnectionManager {
    // Conscrypt TLS 1.3 needs RSA-PSS and a raw/no-padding RSA operation.
    // v3 avoids reusing the incompatible previously generated Keystore identity.
    private static final String KEY_ALIAS = "berry_fcm_adb_identity_v3";
    private static AdbConnectionManager instance;
    private final PrivateKey privateKey;
    private final Certificate certificate;
    private String activeTransport = "";
    private String staticHost = "";
    private int staticPort;
    private final ExecutorService shellWorker = Executors.newSingleThreadExecutor();

    static synchronized AdbConnectionManager get(Context context) throws Exception {
        if (instance == null) instance = new AdbConnectionManager(context.getApplicationContext());
        return instance;
    }

    private AdbConnectionManager(Context context) throws Exception {
        setApi(Build.VERSION.SDK_INT);
        setTimeout(10, TimeUnit.SECONDS);
        KeyStore store = KeyStore.getInstance("AndroidKeyStore");
        store.load(null);
        if (!store.containsAlias(KEY_ALIAS)) {
            KeyPairGenerator generator =
                    KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA, "AndroidKeyStore");
            KeyGenParameterSpec spec = new KeyGenParameterSpec.Builder(KEY_ALIAS,
                    KeyProperties.PURPOSE_SIGN | KeyProperties.PURPOSE_VERIFY)
                    .setKeySize(2048)
                    .setDigests(KeyProperties.DIGEST_NONE, KeyProperties.DIGEST_SHA1,
                            KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA384,
                            KeyProperties.DIGEST_SHA512)
                    .setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PKCS1,
                            KeyProperties.SIGNATURE_PADDING_RSA_PSS)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .build();
            generator.initialize(spec);
            generator.generateKeyPair();
            // This separate identity is for explicit legacy ADB TCP only.
        }
        privateKey = (PrivateKey) store.getKey(KEY_ALIAS, null);
        certificate = store.getCertificate(KEY_ALIAS);
        if (privateKey == null || certificate == null)
            throw new IllegalStateException("无法创建 AndroidKeyStore ADB 身份");
    }

    @NonNull @Override protected PrivateKey getPrivateKey() { return privateKey; }
    @NonNull @Override protected Certificate getCertificate() { return certificate; }
    @NonNull @Override protected String getDeviceName() { return "BerryFCM"; }

    synchronized boolean connectStatic(String host, int port) throws Exception {
        if ("static".equals(activeTransport) && port == staticPort
                && host.equals(staticHost) && isConnected()) return true;
        disconnectSession();
        // Legacy USB-to-TCP setup may legitimately need Android RSA approval.
        setThrowOnUnauthorised(false);
        boolean connected = connect(host, port);
        if (connected) {
            activeTransport = "static";
            staticHost = host;
            staticPort = port;
        }
        return connected;
    }

    /**
     * One bounded ADB transaction. Never keep adbd connected between samples.
     * Pairing credentials are independent of the transport socket.
     */
    synchronized String executeOnce(Context context, String mode, String host, int port,
            String command) throws Exception {
        try {
            if (!AppPrefs.STATIC.equals(mode)) throw new IOException("无线 ADB 必须使用 Priv Kit");
            boolean connected = connectStatic(host, port);
            if (!connected) throw new IOException("ADB 暂未连接");
            String identity = shell("id").trim();
            if (!identity.matches("(?s)^uid=2000(?:\\D.*)?$"))
                throw new IOException("ADB Shell 身份异常");
            return "id".equals(command) ? identity : shell(command);
        } finally {
            disconnectSession();
        }
    }

    synchronized String shell(String command) throws Exception {
        // libadb's connect timeout does not bound command stream reads. Keep
        // the shared transport serialized and cancel a stalled command.
        Future<String> job = shellWorker.submit(() -> readCommand(command));
        try {
            return job.get(75, TimeUnit.SECONDS);
        } catch (TimeoutException timeout) {
            job.cancel(true);
            throw new IOException("ADB Shell 命令 75 秒超时，后台将重新连接", timeout);
        } catch (InterruptedException interrupted) {
            job.cancel(true);
            Thread.currentThread().interrupt();
            throw interrupted;
        } catch (ExecutionException failure) {
            Throwable cause = failure.getCause();
            if (cause instanceof Exception) throw (Exception) cause;
            throw new IOException("ADB Shell 命令失败", cause);
        }
    }

    private String readCommand(String command) throws Exception {
        // Legacy shell:COMMAND avoids PTY input echo. A subshell preserves the
        // completion marker even when a command uses "exit". Do not rely on
        // libadb's peer-close/EOF timing to determine command completion.
        String marker = "__BERRY_DONE_" + UUID.randomUUID().toString().replace("-", "") + "__";
        String destination = "shell:(" + command + "); __berry_rc=$?; printf '\\n"
                + marker + ":%s\\n' \"$__berry_rc\"";
        try (AdbStream stream = openStream(destination);
                InputStream input = stream.openInputStream()) {
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            byte[] buffer = new byte[8192];
            int n;
            while ((n = input.read(buffer)) >= 0) {
                if (n == 0) continue;
                if (output.size() + n > 200000) throw new IOException("ADB Shell 输出超限");
                output.write(buffer, 0, n);
                String text = output.toString(StandardCharsets.UTF_8).replace("\r\n", "\n");
                int start = text.lastIndexOf("\n" + marker + ":");
                if (start < 0) continue;
                int from = start + marker.length() + 2;
                int end = text.indexOf('\n', from);
                if (end < 0) continue;
                String code = text.substring(from, end).trim();
                if (!code.matches("[0-9]+")) throw new IOException("ADB Shell 完成标记异常");
                // Preserve the existing shell API: policy probes may inspect
                // the output of non-zero commands themselves.
                return text.substring(0, start);
            }
            throw new IOException("ADB Shell 未返回命令完成标记");
        }
    }

    synchronized void disconnectSession() {
        activeTransport = "";
        try { disconnect(); } catch (Exception ignored) { }
    }

    @Override public synchronized void close() {
        // Do not destroy the AndroidKeyStore private key.
        disconnectSession();
    }
}
