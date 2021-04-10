use role accountadmin;

create database if not exists redditdb;
create warehouse if not exists redditwh with warehouse_size = 'xsmall' auto_suspend = 60 initially_suspended = true;
use schema redditdb.public;
use database redditdb;

CREATE TABLE REDDIT_ACCOUNTS (
  id number,
  name varchar(100),
  created_utc number,
  updated_on number,
  comment_karma number,
  link_karma number
)

CREATE STORAGE INTEGRATION gcp_storage
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = GCS
  ENABLED = TRUE
  STORAGE_ALLOWED_LOCATIONS = ('*');
  
DESC STORAGE INTEGRATION gcp_storage;

grant usage on integration gcp_storage to sysadmin;

use role sysadmin;

//CSV DATA IMPORT EXAMPLE
create or replace file format reddit_accounts_csv
      type = csv
      field_delimiter = ','
      skip_header = 1
      null_if = ('NULL', 'null')
      empty_field_as_null = true
      compression = gzip;

create stage my_gcs_stage
  url = 'gcs://snowflake905/reddit_accounts'
  storage_integration = gcp_storage
  file_format = reddit_accounts_csv;

copy into REDDIT_ACCOUNTS
  from @my_gcs_stage
