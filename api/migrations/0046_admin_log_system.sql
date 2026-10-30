-- +goose Up
-- Cron jobs started by hand from the admin portal's «System».
ALTER TABLE admin_log DROP CONSTRAINT admin_log_area_check;
ALTER TABLE admin_log ADD CONSTRAINT admin_log_area_check CHECK (area IN ('meldungen', 'nutzer', 'inhalte', 'system'));
-- +goose Down
DELETE FROM admin_log WHERE area = 'system';
ALTER TABLE admin_log DROP CONSTRAINT admin_log_area_check;
ALTER TABLE admin_log ADD CONSTRAINT admin_log_area_check CHECK (area IN ('meldungen', 'nutzer', 'inhalte'));
