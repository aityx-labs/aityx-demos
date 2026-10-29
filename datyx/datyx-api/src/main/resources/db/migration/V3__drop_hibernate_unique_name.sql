-- Databases that Hibernate made before Flyway (baselined as version 1)
-- still have the unique constraint it generated for the data source
-- name, global, from before profiles; the name is unique per profile
-- now (V2's index), so it goes. Nothing to do on a database Flyway made.
alter table data_source drop constraint if exists ukmsgp2h0jmt17kj329439hmixa;
