package datyx.catalog;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.JsonNodeFactory;

/**
 * Whether a column, or a field of a record, holds personal data in the
 * terms of the GDPR, and how sensitive it is, as tags of the two
 * classifications OpenMetadata ships with: PII (None, NonSensitive,
 * Sensitive) on every column and field, and PersonalData (Personal,
 * SpecialCategory) on those that hold personal data. Each tag's reason
 * says why, with the GDPR article.
 *
 * Only names are read, never a value: the table's or topic's, the
 * column's or field's and those of the records a field is in. A record
 * is about a person when its name says so (patients, people.moves, a
 * health encounter such as an admission, but not an hourly count of
 * them), or a column names one (person_id, customer_email, first_name);
 * only then do its columns hold personal data, so a care center's phone
 * is none (the GDPR protects natural persons, Recital 14) and a
 * patient's is. A column about a person is, the first that applies:
 *
 * - SPECIAL: special category data (Art. 9: health, genetic, biometric,
 *   racial or ethnic origin, political opinions, religious beliefs, trade
 *   union membership, sex life or orientation) or criminal data
 *   (Art. 10, kept as special too): PII.Sensitive and
 *   PersonalData.SpecialCategory. In a health care record every fact is
 *   health data (Art. 4(15), Recital 35), and so is a patient's number.
 * - DIRECT: identifies the person directly, or is an online identifier,
 *   precise location, financial data or a secret: PII.Sensitive and
 *   PersonalData.Personal.
 * - QUASI: identifies the person with other data (age, sex, city,
 *   occupation): PII.NonSensitive and PersonalData.Personal.
 * - IDENTIFIER: a key of the record, pseudonymous data, which is still
 *   personal (Recital 26): PII.NonSensitive and PersonalData.Personal.
 * - PERSONAL: anything else that relates to the person (Art. 4(1)):
 *   PII.NonSensitive and PersonalData.Personal.
 *
 * Anything else is NONE: PII.None and no PersonalData tag. A record or
 * array field is the most protected of itself and its fields. These are
 * suggestions from names: a person's own tags (Manual) in either
 * classification win over them, and stay.
 */
public final class Pii {

    public static final String PII = "PII";

    public static final String PERSONAL_DATA = "PersonalData";

    private Pii() {
    }

    /** From least to most protected: a record field is the highest of itself and its fields. */
    public enum Category {
        NONE("None", null),
        PERSONAL("NonSensitive", "Personal"),
        IDENTIFIER("NonSensitive", "Personal"),
        QUASI("NonSensitive", "Personal"),
        DIRECT("Sensitive", "Personal"),
        SPECIAL("Sensitive", "SpecialCategory");

        /** The PII tag. */
        public final String pii;

        /** The PersonalData tag; null when the data isn't personal. */
        public final String personalData;

        Category(String pii, String personalData) {
            this.pii = PII + "." + pii;
            this.personalData = personalData == null ? null : PERSONAL_DATA + "." + personalData;
        }
    }

    /** A column's or field's category, and why, as the tags' reason says it. */
    public record Label(Category category, String reason) {
    }

    // Words, singular and lower case: a name's words match in either form.

    /** Who a record, or a column's prefix, can be about. */
    private static final Set<String> PERSON = Set.of("person", "people", "patient", "user", "customer", "client",
        "member", "employee", "staff", "worker", "contact", "citizen", "resident", "applicant", "candidate", "student",
        "pupil", "guest", "subscriber", "visitor", "passenger", "traveler", "traveller", "doctor", "nurse",
        "physician", "clinician", "practitioner", "caregiver", "tenant", "borrower", "debtor", "beneficiary",
        "policyholder", "insured", "buyer", "shopper", "consumer", "donor", "voter", "spouse", "guardian",
        "individual", "owner", "holder", "author", "sender", "recipient", "requester");

    /** A health encounter: a record of one is about a patient, and its facts are health data. */
    private static final Set<String> ENCOUNTER = Set.of("admission", "triage", "encounter", "appointment",
        "consultation", "discharge", "prescription", "referral", "hospitalization", "hospitalisation", "diagnosis");

    /** A record about a person with one of these in its name is a health care record (Recital 35). */
    private static final Set<String> HEALTH_RECORD = union(ENCOUNTER, Set.of("patient", "health", "medical", "clinical"));

    /** A record of counts or totals over people is about none of them. */
    private static final Set<String> AGGREGATE = Set.of("hourly", "daily", "weekly", "monthly", "quarterly", "yearly",
        "annual", "stat", "statistic", "summary", "total", "count", "aggregate", "agg", "metric", "kpi", "report",
        "rollup", "histogram", "trend");

    /** The last word of a key. */
    private static final Set<String> KEY = Set.of("id", "uuid", "guid", "key", "ref", "reference", "number", "no",
        "nr", "num", "code");

    /** What can say whose a name, an address or a city is, beside the person words: anything else makes it a thing's. */
    private static final Set<String> MODIFIER = Set.of("first", "last", "middle", "full", "given", "family", "maiden",
        "display", "nick", "legal", "preferred", "birth", "home", "street", "postal", "mailing", "billing", "shipping",
        "residential", "residence", "delivery", "personal", "private", "work", "business", "current", "previous",
        "permanent", "primary", "secondary", "alt", "alternate", "alternative", "other", "emergency", "number", "no",
        "num", "nr", "line", "code", "of", "place", "country", "verified");

    /** The words of a person's name that make a column of one wherever it is (first_name). */
    private static final Set<String> NAME_PART = Set.of("first", "last", "middle", "full", "given", "family", "maiden");

    private record Kind(Set<String> words, String reason) {
    }

    private static Kind kind(String reason, String... words) {
        return new Kind(Set.of(words), reason);
    }

    private static final List<Kind> SPECIAL = List.of(
        kind("health data (GDPR Art. 9(1), Art. 4(15))", "health", "medical", "clinical", "diagnosis", "diagnose",
            "diagnostic", "condition", "disease", "illness", "sickness", "symptom", "complaint", "injury",
            "disability", "disabled", "allergy", "allergic", "medication", "medicine", "drug", "prescription",
            "dosage", "dose", "treatment", "therapy", "surgery", "procedure", "icd", "icd10", "snomed", "vital",
            "blood", "pulse", "heart", "bmi", "pregnancy", "pregnant", "mental", "psychiatric", "psychological",
            "hiv", "vaccination", "vaccine", "immunization", "acute", "chronic", "triage", "mrn", "lab", "smoker",
            "smoking", "alcohol"),
        kind("genetic data (GDPR Art. 9(1), Art. 4(13))", "genetic", "gene", "genome", "genomic", "genotype", "dna",
            "chromosome"),
        kind("biometric data (GDPR Art. 9(1), Art. 4(14))", "biometric", "fingerprint", "faceprint", "facial",
            "retina", "iris", "voiceprint"),
        kind("racial or ethnic origin (GDPR Art. 9(1))", "race", "racial", "ethnicity", "ethnic"),
        kind("political opinions (GDPR Art. 9(1))", "political", "politic", "politics"),
        kind("religious or philosophical beliefs (GDPR Art. 9(1))", "religion", "religious", "belief", "faith",
            "philosophical"),
        kind("trade union membership (GDPR Art. 9(1))", "union"),
        kind("sex life or sexual orientation (GDPR Art. 9(1))", "sexual", "sexuality", "orientation"),
        kind("criminal convictions and offences (GDPR Art. 10)", "criminal", "crime", "conviction", "offence",
            "offense", "arrest", "felony", "probation", "parole"));

    /** Identifies a person wherever the column is. */
    private static final List<Kind> DIRECT = List.of(
        kind("a person's name, which identifies them directly (GDPR Art. 4(1))", "firstname", "lastname", "fullname",
            "surname", "forename", "nickname"),
        kind("an identification number (GDPR Art. 4(1), Art. 87)", "ssn", "passport", "nin", "nino", "tin", "cpf",
            "nif", "nie", "nhs", "license", "licence", "national", "social", "taxid"),
        kind("financial data, of high risk if disclosed (GDPR Recital 75)", "iban", "card", "cvv", "cvc", "salary",
            "income", "wage", "credit", "bank"),
        kind("an online identifier (GDPR Art. 4(1), Recital 30)", "ip", "ipaddress", "imei", "macaddress", "cookie",
            "username"),
        kind("a secret, of high risk if disclosed (GDPR Art. 32)", "password", "passwd", "pwd", "secret"));

    /** A person's when nothing but person words and modifiers come with it (home_address, not hospital_address). */
    private static final List<Kind> DIRECT_OWN = List.of(
        kind("a person's name, which identifies them directly (GDPR Art. 4(1))", "name"),
        kind("a person's contact details, which identify them directly (GDPR Art. 4(1))", "email", "emailaddress",
            "mail", "phone", "phonenumber", "telephone", "tel", "mobile", "cell", "fax", "address", "street"),
        kind("location data (GDPR Art. 4(1))", "lat", "latitude", "lon", "lng", "longitude", "geo", "geolocation",
            "gps", "coordinate", "coord"),
        kind("an image of a person (GDPR Art. 4(1), Recital 51)", "photo", "picture", "image", "avatar", "selfie",
            "portrait", "signature"));

    private static final List<Kind> QUASI = List.of(
        kind("identifies a person combined with other data (GDPR Art. 4(1))", "age", "birth", "born", "dob",
            "birthday", "birthdate", "dateofbirth", "sex", "gender", "nationality", "citizenship", "occupation",
            "profession", "job", "employer", "education", "marital", "married"));

    private static final List<Kind> QUASI_OWN = List.of(
        kind("where a person is, which identifies them combined with other data (GDPR Art. 4(1))", "postal", "zip",
            "zipcode", "postcode", "postalcode", "city", "town", "municipality", "region", "county", "district",
            "neighborhood", "neighbourhood", "country", "location", "language", "locale"));

    /** Words that make a record about a person wherever they are, with a person's name (first_name) and birth date. */
    private static final Set<String> PERSONAL_ANYWHERE = Set.of("firstname", "lastname", "fullname", "surname",
        "forename", "ssn", "passport", "dob", "birthday", "birthdate", "dateofbirth", "gender", "sex");

    private static final Pattern SPLIT = Pattern.compile(
        "[^A-Za-z0-9]+|(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])|(?<=[A-Za-z])(?=[0-9])|(?<=[0-9])(?=[A-Za-z])");

    /** A name's words, lower case: patient_id, patientId and PatientID are patient and id. */
    static List<String> words(String name) {
        List<String> words = new ArrayList<>();
        for (String word : SPLIT.split(name == null ? "" : name)) {
            if (!word.isEmpty()) {
                words.add(word.toLowerCase(Locale.ROOT));
            }
        }
        return words;
    }

    /** A word without its plural: admissions, people stay people, address stays. */
    private static String singular(String word) {
        if (word.endsWith("ies") && word.length() > 4) {
            return word.substring(0, word.length() - 3) + "y";
        }
        if (word.endsWith("s") && word.length() > 2 && !word.endsWith("ss") && !word.endsWith("is") && !word.endsWith("us")) {
            return word.substring(0, word.length() - 1);
        }
        return word;
    }

    private static boolean in(Set<String> set, String word) {
        return set.contains(word) || set.contains(singular(word));
    }

    private static boolean any(Set<String> set, List<String> words) {
        return words.stream().anyMatch(w -> in(set, w));
    }

    private static Kind match(List<Kind> kinds, List<String> words) {
        for (Kind kind : kinds) {
            if (any(kind.words(), words)) {
                return kind;
            }
        }
        return null;
    }

    /** A name's other words say it's a person's: person words, modifiers and the kind's own words only. */
    private static boolean own(Kind kind, List<String> words) {
        return words.stream().allMatch(w -> in(kind.words(), w) || in(PERSON, w) || in(MODIFIER, w)
            || w.chars().allMatch(Character::isDigit));
    }

    private static boolean isKey(List<String> words) {
        return !words.isEmpty() && in(KEY, words.get(words.size() - 1));
    }

    private static boolean personName(List<String> words) {
        return words.contains("name") && any(NAME_PART, words);
    }

    /** Whether a record's name says it's about a person: a person or a health encounter, but not a count of them. */
    private static boolean aboutPerson(List<String> recordWords) {
        return (any(PERSON, recordWords) || any(ENCOUNTER, recordWords)) && !any(AGGREGATE, recordWords);
    }

    /** Whether a column makes its record about a person: person_id, customer_email, first_name, ssn. */
    private static boolean namesPerson(List<String> words) {
        if (any(PERSONAL_ANYWHERE, words) || personName(words)
                || words.contains("birth") && (words.contains("date") || words.contains("day") || words.contains("place"))) {
            return true;
        }
        return any(PERSON, words) && (isKey(words) || match(DIRECT, words) != null || match(DIRECT_OWN, words) != null
            || match(QUASI, words) != null || match(QUASI_OWN, words) != null);
    }

    /**
     * The labels of a table's columns or a topic's fields, by where each is
     * in {@code items} as a JSON Pointer relative to it ("0",
     * "2/children/1"). {@code items} is OpenMetadata's columns or
     * schemaFields: each with a name, a record's or array's with children.
     */
    public static Map<String, Label> labels(String entity, JsonNode items) {
        Map<String, Label> labels = new LinkedHashMap<>();
        label(words(entity), false, false, items, "", labels);
        return labels;
    }

    /** Labels {@code items} into {@code into}, and answers the most protected of them; null for none. */
    private static Label label(List<String> recordWords, boolean person, boolean health, JsonNode items, String prefix,
            Map<String, Label> into) {
        boolean about = person || aboutPerson(recordWords);
        for (JsonNode item : items) {
            about = about || namesPerson(words(item.path("name").asText()));
        }
        boolean healthRecord = about && (health || any(HEALTH_RECORD, recordWords));
        Label highest = null;
        for (int i = 0; i < items.size(); i++) {
            JsonNode item = items.get(i);
            String name = item.path("name").asText();
            List<String> words = words(name);
            Label label = category(words, about, healthRecord);
            JsonNode children = item.path("children");
            if (children.isArray() && !children.isEmpty()) {
                Label inside = label(words, about, healthRecord, children, prefix + i + "/children/", into);
                if (inside != null && inside.category().compareTo(label.category()) > 0) {
                    label = new Label(inside.category(), "holds " + inside.reason());
                }
            }
            into.put(prefix + i, label);
            if (highest == null || label.category().compareTo(highest.category()) > 0) {
                highest = label;
            }
        }
        return highest;
    }

    /** A column's or field's label by its words, in a record about a person or not, and a health care record or not. */
    static Label category(List<String> words, boolean about, boolean healthRecord) {
        if (!about) {
            return new Label(Category.NONE, "not about a person, so not personal data (GDPR Art. 4(1), Recital 26)");
        }
        Kind kind = match(SPECIAL, words);
        if (kind != null) {
            return new Label(Category.SPECIAL, kind.reason());
        }
        if (personName(words)) {
            return new Label(Category.DIRECT, DIRECT.get(0).reason());
        }
        kind = match(DIRECT, words);
        if (kind != null) {
            return new Label(Category.DIRECT, kind.reason());
        }
        kind = match(DIRECT_OWN, words);
        if (kind != null && own(kind, words)) {
            return new Label(Category.DIRECT, kind.reason());
        }
        kind = match(QUASI, words);
        if (kind != null) {
            return new Label(Category.QUASI, kind.reason());
        }
        kind = match(QUASI_OWN, words);
        if (kind != null && own(kind, words)) {
            return new Label(Category.QUASI, kind.reason());
        }
        if (isKey(words)) {
            return healthRecord && words.stream().anyMatch(w -> in(Set.of("patient"), w))
                ? new Label(Category.SPECIAL, "a patient's number, health data (GDPR Art. 9(1), Recital 35)")
                : new Label(Category.IDENTIFIER, "a key of a person's record, pseudonymous personal data (GDPR Art. 4(5), Recital 26)");
        }
        return healthRecord
            ? new Label(Category.SPECIAL, "part of a person's health care record, health data (GDPR Art. 9(1), Recital 35)")
            : new Label(Category.PERSONAL, "relates to a person, personal data (GDPR Art. 4(1))");
    }

    /**
     * A column's or field's tags with {@code label}'s: its tags of other
     * classifications kept, and in PII and in PersonalData a person's own
     * tags (any but Automated) kept, else datyx's (Automated) replaced by
     * the label's.
     */
    public static ArrayNode tags(JsonNode current, Label label) {
        JsonNodeFactory nodes = JsonNodeFactory.instance;
        ArrayNode tags = nodes.arrayNode();
        Set<String> decided = new HashSet<>();
        for (JsonNode tag : current) {
            String classification = classificationOf(tag.path("tagFQN").asText());
            if (classification == null) {
                tags.add(tag);
            } else if (!"Automated".equals(tag.path("labelType").asText())) {
                tags.add(tag);
                decided.add(classification);
            }
        }
        if (!decided.contains(PII)) {
            tags.add(tag(label.category().pii, label.reason()));
        }
        if (!decided.contains(PERSONAL_DATA) && label.category().personalData != null) {
            tags.add(tag(label.category().personalData, label.reason()));
        }
        return tags;
    }

    private static JsonNode tag(String fqn, String reason) {
        return JsonNodeFactory.instance.objectNode()
            .put("tagFQN", fqn)
            .put("source", "Classification")
            .put("labelType", "Automated")
            .put("state", "Confirmed")
            .put("reason", reason);
    }

    /** PII or PersonalData for one of their tags; null for another classification's. */
    static String classificationOf(String fqn) {
        if (fqn.startsWith(PII + ".")) {
            return PII;
        }
        return fqn.startsWith(PERSONAL_DATA + ".") ? PERSONAL_DATA : null;
    }

    /** Whether two tag lists say the same: the same tags, each with the same reason, in any order. */
    public static boolean same(JsonNode a, JsonNode b) {
        return signature(a).equals(signature(b));
    }

    private static Set<String> signature(JsonNode tags) {
        Set<String> names = new HashSet<>();
        tags.forEach(tag -> names.add(tag.path("tagFQN").asText() + "\n" + tag.path("labelType").asText()
            + "\n" + tag.path("reason").asText("")));
        return names;
    }

    private static Set<String> union(Set<String> a, Set<String> b) {
        Set<String> all = new HashSet<>(a);
        all.addAll(b);
        return Set.copyOf(all);
    }
}
