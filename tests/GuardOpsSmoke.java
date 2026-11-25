package top.zesun.berryfcm;

import java.util.HashSet;
import java.util.Set;

public final class GuardOpsSmoke {
    public static void main(String[] args) {
        Set<String> apps = new HashSet<>();
        for (int i = 0; i < 25; i++) apps.add("org.berryfcm.test.app" + i);
        String check = GuardOps.command(apps, false);
        String repair = GuardOps.command(apps, true);
        for (String app : apps) {
            if (!check.contains("p='" + app + "'") || !repair.contains("p='" + app + "'"))
                throw new AssertionError("Selected guard target omitted: " + app);
        }
        if (!check.contains("p='" + GuardOps.GMS + "'"))
            throw new AssertionError("Core Google Play services target omitted");
        if (!check.contains("dumpsys -t 3 package"))
            throw new AssertionError("Read-only status must retain auxiliary package diagnostics");
        if (repair.contains("dumpsys") || !repair.contains("cmd package unstop --user 0")
                || !repair.contains("|unstop_submitted"))
            throw new AssertionError("Repair must unstop without dump gating or false recheck");
        java.util.List<String> batches = GuardOps.commandBatches(apps, true);
        if (batches.size() != 6) throw new AssertionError("wrong batch count");
        String joined = String.join("\n", batches);
        for (String app : apps) {
            String needle = "p='" + app + "'";
            if (joined.indexOf(needle) < 0 || joined.indexOf(needle) != joined.lastIndexOf(needle))
                throw new AssertionError("Missing or duplicate target " + app);
        }
        String gms = "p='" + GuardOps.GMS + "'";
        if (joined.indexOf(gms) < 0 || joined.indexOf(gms) != joined.lastIndexOf(gms))
            throw new AssertionError("GMS must appear once");
        for (String batch : batches) if (batch.split("p='", -1).length - 1 > 5)
            throw new AssertionError("Batch exceeds bounded shell duration");
        System.out.println("PASS: selected guard targets are not silently truncated; bounded batches and one GMS target");
    }
}
