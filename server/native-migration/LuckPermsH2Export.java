import java.nio.charset.StandardCharsets;
import java.sql.*;
import java.util.Base64;
import java.util.Properties;
import java.util.Set;
import java.util.TreeMap;

class LuckPermsH2Export {
    private static String encoded(String value) {
        return value == null ? "!" : Base64.getEncoder().encodeToString(
            value.getBytes(StandardCharsets.UTF_8));
    }

    public static void main(String[] args) throws Exception {
        Set<String> expected = Set.of("luckperms_actions", "luckperms_groups",
            "luckperms_group_permissions", "luckperms_players",
            "luckperms_tracks", "luckperms_user_permissions");
        try (Connection connection = DriverManager.getConnection(
                "jdbc:h2:" + args[0] + ";ACCESS_MODE_DATA=r;IFEXISTS=TRUE", new Properties())) {
            TreeMap<String, String> tables = new TreeMap<>();
            try (ResultSet metadata = connection.getMetaData().getTables(null, "PUBLIC", "%", null)) {
                while (metadata.next()) {
                    String table = metadata.getString("TABLE_NAME");
                    if (table.toLowerCase(java.util.Locale.ROOT).startsWith("luckperms_")) {
                        tables.put(table.toLowerCase(java.util.Locale.ROOT), table);
                    }
                }
            }
            if (!tables.keySet().equals(expected)) {
                throw new IllegalStateException("Unexpected H2 LuckPerms table set: " + tables.keySet());
            }
            for (var entry : tables.entrySet()) {
                try (Statement statement = connection.createStatement();
                     ResultSet rows = statement.executeQuery(
                         "SELECT * FROM \"" + entry.getValue().replace("\"", "\"\"") + "\"")) {
                    ResultSetMetaData metadata = rows.getMetaData();
                    StringBuilder header = new StringBuilder("TABLE\t" + entry.getKey());
                    for (int column = 1; column <= metadata.getColumnCount(); column++) {
                        header.append("\t").append(metadata.getColumnName(column).toLowerCase(
                            java.util.Locale.ROOT));
                    }
                    System.out.println(header);
                    while (rows.next()) {
                        StringBuilder line = new StringBuilder("ROW");
                        for (int column = 1; column <= metadata.getColumnCount(); column++) {
                            line.append("\t").append(encoded(rows.getString(column)));
                        }
                        System.out.println(line);
                    }
                }
            }
        }
    }
}
