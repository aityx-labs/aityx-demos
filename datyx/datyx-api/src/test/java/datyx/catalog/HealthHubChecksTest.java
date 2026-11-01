package datyx.catalog;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.Set;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.quarkus.test.junit.QuarkusTest;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * HealthHub's curation document against HealthHub's schema, made on the
 * Dev Services Postgres from catalog/healthhub-fixture.sql (the tables
 * and views of HealthHub's lib/db.dart) with a few rows of correct data:
 * every table the document curates is there, every check is on a column
 * it has, its definition is one datyx runs and its name is its table's
 * only one, and every check passes on correct data. Then defects the
 * checks are there to catch, each failing its check.
 */
@QuarkusTest
class HealthHubChecksTest {

    private static final ObjectMapper JSON = new ObjectMapper();

    private static final String SCHEMA = "healthhub_fixture";

    @ConfigProperty(name = "quarkus.datasource.jdbc.url")
    String jdbcUrl;

    @ConfigProperty(name = "quarkus.datasource.username")
    String username;

    @ConfigProperty(name = "quarkus.datasource.password")
    String password;

    private Curation.Doc doc;

    /** A connection whose unqualified names are HealthHub's tables, as the source's are. */
    private Connection connect() throws SQLException {
        Properties props = new Properties();
        props.setProperty("user", username);
        props.setProperty("password", password);
        props.setProperty("options", "-c search_path=" + SCHEMA);
        return DriverManager.getConnection(jdbcUrl, props);
    }

    @BeforeEach
    void fixture() throws Exception {
        String sql;
        try (InputStream in = getClass().getClassLoader().getResourceAsStream("catalog/healthhub-fixture.sql")) {
            sql = new String(in.readAllBytes(), StandardCharsets.UTF_8);
        }
        try (Connection c = connect(); Statement s = c.createStatement()) {
            s.execute("drop schema if exists " + SCHEMA + " cascade");
            s.execute("create schema " + SCHEMA);
            s.execute(sql);
        }
        try (InputStream in = getClass().getClassLoader().getResourceAsStream(DevCatalog.DOCUMENT)) {
            doc = JSON.readValue(in, Curation.Doc.class);
        }
    }

    private Map<String, SchemaReader.Table> tables(Connection c) throws SQLException {
        Map<String, SchemaReader.Table> tables = new LinkedHashMap<>();
        for (SchemaReader.Table table : SchemaReader.read(c)) {
            if (table.schema().equals(SCHEMA)) {
                tables.put("public." + table.name(), table);
            }
        }
        return tables;
    }

    /** Each check of the document's table, by name, run on the fixture. */
    private Map<String, Quality.Result> run(String table) throws SQLException {
        Map<String, Quality.Result> results = new LinkedHashMap<>();
        try (Connection c = connect()) {
            SchemaReader.Table source = tables(c).get(table);
            for (Quality.Check check : doc.tables().get(table).checks()) {
                results.put(check.name(), Quality.evaluate(c, source, check));
            }
        }
        return results;
    }

    private void write(String sql) throws SQLException {
        try (Connection c = connect(); Statement s = c.createStatement()) {
            s.execute(sql);
        }
    }

    private void failsOnly(String table, String... names) throws SQLException {
        List<String> failed = new ArrayList<>();
        run(table).forEach((name, result) -> {
            if (!result.passed()) {
                failed.add(name);
            }
        });
        assertEquals(List.of(names), failed, table);
    }

    @Test
    void everyCheckIsOnHealthHubsSchemaAndPassesOnCorrectData() throws Exception {
        int checks = 0;
        try (Connection c = connect()) {
            Map<String, SchemaReader.Table> tables = tables(c);
            assertEquals(doc.tables().keySet(), tables.keySet(), "the document curates every table and view of HealthHub");
            for (var entry : doc.tables().entrySet()) {
                SchemaReader.Table source = tables.get(entry.getKey());
                assertNotNull(source, entry.getKey());
                Set<String> names = new HashSet<>();
                Quality.fromSchema(source).forEach(check -> names.add(check.name()));
                for (Quality.Check check : entry.getValue().checks()) {
                    String what = entry.getKey() + " " + check.name();
                    assertTrue(Quality.TESTS.contains(check.test()), what);
                    assertTrue(Quality.applies(source, check), what + ": no such column");
                    assertTrue(names.add(check.name()), what + ": another check, or the schema's, has its name");
                    assertTrue(check.description() != null && check.description().length() > 10, what);
                    Quality.Result result = Quality.evaluate(c, source, check);
                    assertTrue(result.passed(), what + ": " + result.result());
                    checks++;
                }
                for (Quality.Check check : Quality.fromSchema(source)) {
                    assertTrue(Quality.evaluate(c, source, check).passed(), entry.getKey() + " " + check.name());
                }
            }
        }
        assertTrue(checks > 120, checks + " checks");
    }

    @Test
    void admissionsDefects() throws Exception {
        write("update admissions set sim_day = 2, age = 17 where event_id = 'a1b2c3d4-reus-1-d1-t5'");
        failsOnly("public.admissions", "age_columnValuesToBeBetween", "tableCustomSQLQuery_event_id_matches_its_row",
            "tableCustomSQLQuery_person_keeps_their_facts", "tableCustomSQLQuery_age_fits_the_condition");
        fixture();
        write("update admissions set hospital_name = 'Hospital del Mar', complaint = 'Hello, I''m {name}, I cough a lot.'"
            + " where id = 1");
        failsOnly("public.admissions", "complaint_columnValuesToNotMatchRegex",
            "tableCustomSQLQuery_hospital_is_a_care_center");
        fixture();
        write("update medical_conditions set name = 'Bronchitis' where code = 'acute_bronchitis'");
        failsOnly("public.admissions", "tableCustomSQLQuery_condition_is_in_the_seed");
    }

    @Test
    void triageDefects() throws Exception {
        write("update admission_triage set wait_minutes = 10, reference = 'red' where event_id = 'a1b2c3d4-reus-1-d1-t5'");
        failsOnly("public.admission_triage", "tableCustomSQLQuery_wait_is_the_levels",
            "tableCustomSQLQuery_reference_is_the_templates");
        fixture();
        // A call of aityx's slowest that its timeouts still allow (10 s connecting, 60 s sending, 60 s reading),
        // answered or timed out: correct; past 180 s, the client hung.
        write("update admission_triage set millis = 130500 where event_id = 'a1b2c3d4-reus-1-d1-t5'");
        failsOnly("public.admission_triage");
        write("update admission_triage set millis = 200000 where event_id = 'a1b2c3d4-reus-1-d1-t5'");
        failsOnly("public.admission_triage", "millis_columnValuesToBeBetween");
        fixture();
        write("alter table admission_triage drop constraint admission_triage_check");
        write("update admission_triage set error = 'late' where event_id = 'a1b2c3d4-reus-1-d1-t5'");
        failsOnly("public.admission_triage", "tableCustomSQLQuery_level_or_error");
    }

    @Test
    void hourlyCountsMustBeTheAdmissions() throws Exception {
        write("update admissions_hourly set admissions = 2 where hour_start = '2026-01-01 09:00'");
        failsOnly("public.admissions_hourly", "tableCustomSQLQuery_acute_and_chronic_add_up",
            "tableCustomSQLQuery_no_count_beyond_the_admissions");
        fixture();
        // Flink counted an hour the admissions table doesn't have: the feed lost it.
        write("insert into admissions_hourly values ('a1b2c3d4', 3, 'JACKSON MEMORIAL HOSPITAL', '2026-01-02 03:00', 1, 1, 0)");
        failsOnly("public.admissions_hourly", "tableCustomSQLQuery_no_count_beyond_the_admissions");
        fixture();
        // Flink counted fewer, or not yet (a restart recounting the topic, an hour at the edge of its retention):
        // information, not a failure.
        write("delete from admissions_hourly where hour_start = '2026-01-01 09:00'");
        failsOnly("public.admissions_hourly");
        Quality.Result short_ = run("public.admissions_hourly").get("tableCustomSQLQuery_hours_counted_short");
        assertEquals("1", short_.values().get("resultRowCount"), short_.result());
        fixture();
        assertEquals("0", run("public.admissions_hourly").get("tableCustomSQLQuery_hours_counted_short").values()
            .get("resultRowCount"));
        // The latest hour isn't settled yet, nor a run's admissions recorded a moment ago: not compared.
        write("delete from admissions_hourly where hour_start = '2026-01-05 08:00'");
        write("insert into admissions (event_id, person_id, person_name, age, sex, occupation, city, condition_code,"
            + " condition_name, condition_type, visit, visit_number, complaint, template, hospital_id, hospital_name,"
            + " sim_day, sim_time) values ('a1b2c3d4-reus-1-d9-t20', 'reus-1', 'Rosa Moreno', 30, 'woman', 'cleaner',"
            + " 'Reus', 'acute_bronchitis', 'Acute bronchitis', 'acute', 'first', 1, 'Hello, I''m Rosa, 30, coughing.',"
            + " 0, 2, 'Centre Mq Reus', 9, '12:00')");
        assertTrue(run("public.admissions_hourly").get("tableCustomSQLQuery_no_count_beyond_the_admissions").passed());
        assertEquals("0", run("public.admissions_hourly").get("tableCustomSQLQuery_hours_counted_short").values()
            .get("resultRowCount"), "nor counted short");
        fixture();
        write("insert into admissions_hourly values ('a1b2c3d4', 99, 'Nowhere', '2026-01-01 09:30', 1, 1, 0)");
        failsOnly("public.admissions_hourly", "tableCustomSQLQuery_on_the_hour",
            "tableCustomSQLQuery_hospital_is_a_care_center", "tableCustomSQLQuery_no_count_beyond_the_admissions");
    }

    @Test
    void careCentersAndConditionsDefects() throws Exception {
        write("update care_centers set latitude = 1.107, longitude = 41.155, website = 'http://app/intranet/' where id = 2");
        failsOnly("public.care_centers", "website_columnValuesToMatchRegex", "tableCustomSQLQuery_coordinates_in_the_country");
        fixture();
        write("delete from complaint_templates where condition_code = 'type_2_diabetes' and visit = 'last' and position = 2");
        write("update medical_conditions set treatment_duration_days = 30 where code = 'type_2_diabetes'");
        failsOnly("public.medical_conditions", "tableCustomSQLQuery_treatment_days_for_acute_only",
            "tableCustomSQLQuery_nine_templates_each");
        fixture();
        write("update complaint_templates set text = text || ' My {pet} is fine.' where id = 1");
        failsOnly("public.complaint_templates", "tableCustomSQLQuery_placeholders_are_known");
    }

    @Test
    void viewsDefects() throws Exception {
        // A visit of a condition the seed no longer has: its stay is unknown.
        write("alter table complaint_templates drop constraint complaint_templates_condition_code_fkey");
        write("delete from medical_conditions where code = 'acute_bronchitis'");
        assertFalse(run("public.patient_days").get("stay_hours_columnValuesToBeNotNull").passed());
        assertFalse(run("public.admissions").get("tableCustomSQLQuery_condition_is_in_the_seed").passed());
        fixture();
        // A condition neither acute nor chronic: its visits count in neither.
        write("update admissions set condition_type = 'other' where id = 1");
        failsOnly("public.patient_days", "tableCustomSQLQuery_visits_add_up");
        fixture();
        // Stays counted past the run's now, and arrivals not counted.
        write("""
            create or replace view occupancy_hourly as
            select split_part(a.event_id, '-', 1) as run_id, a.hospital_id, max(a.hospital_name) as hospital_name,
              hour_start, count(distinct a.person_id)::int as occupancy
            from admissions a,
              generate_series(timestamp '2026-01-01' + (a.sim_day - 1) * interval '1 day' + interval '12 hours',
                timestamp '2026-01-01' + a.sim_day * interval '1 day', interval '1 hour') as hour_start
            group by 1, 2, 4""");
        failsOnly("public.occupancy_hourly", "tableCustomSQLQuery_arrivals_are_in_care",
            "tableCustomSQLQuery_not_ahead_of_the_run");
    }
}
