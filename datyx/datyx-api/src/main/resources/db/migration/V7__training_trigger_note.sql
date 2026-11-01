-- Why a run was queued, in words, when its trigger says more than its
-- name: an ENABLED run (the group switched on) names the change in
-- OpenMetadata, the table's version, who made it and when.

alter table training_run add column trigger_note varchar(500);
