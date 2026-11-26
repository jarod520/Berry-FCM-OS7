package top.zesun.berryfcm;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.StandardOpenOption;
import java.util.Arrays;

final class DiagnosticHistory {
    private static final long DAY_SECONDS = 86400;
    private static final long RETENTION_SECONDS = 2 * DAY_SECONDS;

    private DiagnosticHistory() {}

    static synchronized void append(File directory, String stream, long epoch,
            String legacy, String line) throws IOException {
        if (!directory.isDirectory() && !directory.mkdirs())
            throw new IOException("无法创建诊断日志目录");
        long day = epoch / DAY_SECONDS;
        File current = new File(directory, stream + "." + day);
        String content = (legacy.isEmpty() ? "" : legacy.trim() + "\n") + line + "\n";
        Files.write(current.toPath(), content.getBytes(StandardCharsets.UTF_8),
                StandardOpenOption.CREATE, StandardOpenOption.APPEND);
        for (File file : archives(directory, stream)) {
            long end = (Long.parseLong(file.getName().substring(stream.length() + 1)) + 1) * DAY_SECONDS;
            if (end <= epoch - RETENTION_SECONDS && file.lastModified() / 1000 <= epoch - RETENTION_SECONDS)
                file.delete();
        }
    }

    static synchronized String read(File directory, String stream, String legacy, int limit)
            throws IOException {
        StringBuilder history = new StringBuilder(legacy.trim());
        for (File file : archives(directory, stream)) {
            if (history.length() > 0) history.append('\n');
            history.append(new String(Files.readAllBytes(file.toPath()), StandardCharsets.UTF_8).trim());
        }
        if (limit == 0 || history.length() == 0) return history.toString();
        int start = history.length();
        for (int remaining = limit; remaining > 0 && start > 0; remaining--)
            start = history.lastIndexOf("\n", start - 1);
        return history.substring(Math.max(0, start + 1));
    }

    private static File[] archives(File directory, String stream) {
        File[] files = directory.listFiles((parent, name) -> name.matches(stream + "\\.[0-9]{1,8}"));
        if (files == null) return new File[0];
        Arrays.sort(files, (first, second) -> Long.compare(
                Long.parseLong(first.getName().substring(stream.length() + 1)),
                Long.parseLong(second.getName().substring(stream.length() + 1))));
        return files;
    }
}
