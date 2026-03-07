-- 1. Create the user 'wespa' that can connect from any host (%)
--    (Use 'localhost' instead of '%' if connections only come from the same machine)
CREATE USER 'wespa'@'%' IDENTIFIED BY 'xxx';

-- 2. Grant ALL privileges on the 'wespa' database
GRANT ALL PRIVILEGES ON wespa.* TO 'wespa'@'%';

-- 3. Grant ALL privileges on the 'wespaprod' database
GRANT ALL PRIVILEGES ON wespaprod.* TO 'wespa'@'%';

-- 4. Apply the changes immediately
FLUSH PRIVILEGES;
