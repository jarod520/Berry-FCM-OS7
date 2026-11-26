package top.zesun.berryfcm;

import java.io.File;
import java.nio.file.Files;

public final class DiagnosticHistorySmoke {
    public static void main(String[] args) throws Exception {
        File directory = new File(args[0]);
        String stream = "runtime_events";
        expect("", DiagnosticHistory.read(directory, stream, "", 36));
        Files.createDirectory(directory.toPath());
        expect("", DiagnosticHistory.read(directory, stream, "", 36));
        long epoch = System.currentTimeMillis() / 1000;
        Files.createFile(new File(directory, stream + "." + epoch / 86400).toPath());
        expect("", DiagnosticHistory.read(directory, stream, "", 36));
        expect("旧日志", DiagnosticHistory.read(directory, stream, "旧日志", 36).trim());
        DiagnosticHistory.append(directory, stream, epoch, "", "第一条");
        expect("第一条", DiagnosticHistory.read(directory, stream, "", 36));
        DiagnosticHistory.append(directory, stream, epoch, "", "第二条");
        expect("第一条\n第二条", DiagnosticHistory.read(directory, stream, "", 0));
        expect("第二条", DiagnosticHistory.read(directory, stream, "", 1));
    }

    private static void expect(String expected, String actual) {
        if (!expected.equals(actual))
            throw new AssertionError("预期 [" + expected + "]，实际 [" + actual + "]");
    }
}
