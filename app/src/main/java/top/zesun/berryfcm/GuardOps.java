package top.zesun.berryfcm;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Set;
import java.util.regex.Pattern;

/** Conservative application stopped-state checks. No AccessibilityService. */
final class GuardOps {
    static final String GMS = "com.google.android.gms";
    private static final Pattern PACKAGE = Pattern.compile("[a-zA-Z_][a-zA-Z0-9_]*(\\.[a-zA-Z_][a-zA-Z0-9_]*)+");
    private GuardOps() {}

    static String heartbeatCommand() {
        // A completed broadcast only means the request was accepted, not that
        // FCM has reconnected or delivered a push message.
        return "am broadcast --user 0 -a com.google.android.intent.action.MCS_HEARTBEAT "
                + "-p com.google.android.gms 2>&1";
    }

    static String command(Set<String> selected, boolean repair) {
        return commandFor(targets(selected), repair);
    }

    private static List<String> targets(Set<String> selected) {
        List<String> items = new ArrayList<>(selected);
        if (!items.contains(GMS)) items.add(GMS);
        Collections.sort(items);
        return items;
    }

    // Status-only batches use one bounded package diagnostic per target;
    // repair batches use package-manager commands and never depend on dumpsys.
    static List<String> commandBatches(Set<String> selected, boolean repair) {
        return commandBatches(selected, repair, 5);
    }
    static List<String> commandBatches(Set<String> selected, boolean repair, int batchSize) {
        if (batchSize < 1 || batchSize > 5) throw new IllegalArgumentException("Invalid batch size");
        List<String> items = targets(selected);
        List<String> batches = new ArrayList<>();
        for (int i = 0; i < items.size(); i += batchSize)
            batches.add(commandFor(items.subList(i, Math.min(i + batchSize, items.size())), repair));
        return batches;
    }

    private static String commandFor(List<String> items, boolean repair) {
        StringBuilder cmd = new StringBuilder();
        for (String pkg : items) {
            if (!PACKAGE.matcher(pkg).matches()) continue;
            cmd.append("p='").append(pkg).append("'; ");
            if (repair) {
                cmd.append("if cmd package path --user 0 \"$p\" >/dev/null 2>&1 || ")
                   .append("pm path --user 0 \"$p\" >/dev/null 2>&1; then ")
                   .append("if cmd package unstop --user 0 \"$p\" >/dev/null 2>&1; then ")
                   .append("echo \"$p|unstop_submitted\"; else echo \"$p|repair_failed\"; fi; ")
                   .append("else echo \"$p|not_installed\"; fi; ");
            } else {
                cmd.append("l=\"$(dumpsys -t 3 package \"$p\" 2>/dev/null | ")
                   .append("grep -E '^[[:space:]]*User 0:.*installed=' | head -n 1)\"; ")
                   .append("case \" $l \" in *' installed=false '*) echo \"$p|unknown\";; ")
                   .append("*' stopped=true '*) echo \"$p|stopped\";; ")
                   .append("*' stopped=false '*) echo \"$p|not_stopped\";; ")
                   .append("*) echo \"$p|unknown\";; esac; ");
            }
        }
        return cmd.toString();
    }
}
