package datyx.hello;

import java.time.Instant;

import io.quarkus.hibernate.orm.panache.PanacheEntity;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;

/**
 * A greeting on record (table greeting): what /api/greetings stores and
 * lists. The first Panache entity, so Hibernate keeps the schema.
 */
@Entity
@Table(name = "greeting")
public class Greeting extends PanacheEntity {

    @Column(nullable = false, length = 200)
    public String message;

    @Column(name = "created_at", nullable = false)
    public Instant createdAt;

    /** The newest first, at most {@code limit}. */
    public static java.util.List<Greeting> newest(int limit) {
        return findAll(io.quarkus.panache.common.Sort.descending("createdAt", "id"))
            .page(0, limit).list();
    }
}
