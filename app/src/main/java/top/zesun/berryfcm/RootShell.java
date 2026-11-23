package top.zesun.berryfcm;

import android.content.Context;
import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.concurrent.TimeUnit;

/** Bounded, non-interactive root commands, with no indefinitely blocked pipe. */
final class RootShell implements PrivilegeShell {
    private final Context context;
    RootShell(Context context) { this.context = context.getApplicationContext(); }

    @Override public String execute(String command) throws Exception {
        File output = File.createTempFile("berry-root-", ".txt", context.getCacheDir());
        Process process = null;
        try {
            process = new ProcessBuilder("su", "-c",
                    "if [ \"$(id -u)\" != 0 ]; then echo 'Root UID verification failed'; exit 13; fi; (" + command + ")")
                    .redirectErrorStream(true).redirectOutput(output).start();
            if (!process.waitFor(75, TimeUnit.SECONDS))
                throw new IOException("Root Shell 命令 75 秒超时");
            if (output.length() > 200000) throw new IOException("Root Shell 输出超限");
            String text = new String(Files.readAllBytes(output.toPath()), StandardCharsets.UTF_8);
            if (process.exitValue() != 0)
                throw new IOException("Root Shell exit " + process.exitValue() + ": "
                        + (text.length() > 220 ? text.substring(0, 220) : text));
            return text;
        } finally {
            if (process != null && process.isAlive()) process.destroyForcibly();
            output.delete();
        }
    }
    @Override public void close() { }
}
