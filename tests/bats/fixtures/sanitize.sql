-- Replace the personal data and remove the log entries that mention it.
UPDATE `users_field_data` SET `name` = CONCAT('user ', `uid`, ' 🧹'), `mail` = CONCAT('user+', `uid`, '@localhost'), `init` = CONCAT('user+', `uid`, '@localhost') WHERE `uid` > 0;
TRUNCATE TABLE `watchdog`;
