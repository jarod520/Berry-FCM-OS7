package top.zesun.berryfcm;

import android.content.Context;
import android.os.Binder;
import android.os.Process;
import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.concurrent.TimeUnit;

/** Shizuku v13 supplies BerryFCM's package Context in the privileged process. */
public final class BerryShellUserService extends IBerryShell.Stub {
    private final int ownerUid;

    public BerryShellUserService(Context context) {
        ownerUid = context.getApplicationInfo().uid;
        if (ownerUid < 10000 || (Process.myUid() != 0 && Process.myUid() != 2000))
            throw new SecurityException("Invalid UserService identity");
    }

    @Override public void destroy() {
        int caller = Binder.getCallingUid();
        if (caller != ownerUid && caller != 0 && caller != 2000)
            throw new SecurityException("Unexpected UserService caller");
        System.exit(0);
    }

    @Override public String execute(String command) {
        // The Shizuku broker grants this binder to BerryFCM, not other apps.
        if (Binder.getCallingUid() != ownerUid)
            throw new SecurityException("BerryFCM app UID required");
        if (command == null || command.length() > 160000)
            throw new IllegalArgumentException("Invalid command size");
        File output = null;
        java.lang.Process process = null;
        try {
            output = Files.createTempFile(new File("/data/local/tmp").toPath(),
                    "berry-fcm-", ".log").toFile();
            process = new ProcessBuilder("/system/bin/sh", "-c", command)
                    .redirectErrorStream(true).redirectOutput(output).start();
            if (!process.waitFor(75, TimeUnit.SECONDS))
                throw new IOException("Shell command timeout");
            if (output.length() > 200000) throw new IOException("Shell output limit");
            return new String(Files.readAllBytes(output.toPath()), StandardCharsets.UTF_8);
        } catch (Exception error) {
            throw new IllegalStateException("Shizuku Shell: " + error.getMessage());
        } finally {
            if (process != null && process.isAlive()) process.destroyForcibly();
            if (output != null) output.delete();
        }
    }
}
