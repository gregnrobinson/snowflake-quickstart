# Overview

Snowflake has been appearing all over my linkedin as of late so I thought I would dig into what it is and how it works. Snowflake at its base is a cloud native data platform that removes much of the operational overhead. You can chose to deploy the Snowflake stack on AWS, Azure or GCP. The Stack deployment is completely abstracted from the end user and once you sign up you can start creating warehouses and databases immediately. For more information on Snowflake go [here](https://docs.snowflake.com/en/user-guide-intro.html)

In order to use Snowflake and query a dataset, we need to have a data set to work with. This walkthrough will explain how you can import large datasets from object storage in GCS directly into a Snowflake table.

![alt text](https://community.phronesis.cloud/uploads/default/original/1X/9235e443027b68309b0bc84bc00f1e81fd11b800.png)

# Prepare the Environment

1. Go to https://snowflake.com and sign up for a free trial. Snowflake will give you a 30 day trial with no credit card required. You will be asked to chose a cloud platform to host the Snowflake environment. Since we are using GCS as the data source chose Google Cloud Platform.

2. We now need to source a data set. We will use Pushshift to download a dataset which contains 78 Million user accounts. The size is about 1GB. and can be found [here](https://files.pushshift.io/reddit/69M_reddit_accounts.csv.gz).

    - The downloaded file is a CSV and it is compressed using gzip.

3. We can now upload the dataset to GCS. Use the following two commands to upload the dataset to a new GCS bucket. 

       gsutil mb gs://reddit_accounts
       gsutil cp ~/Downloads/69M_reddit_accounts.csv.gz gs://reddit_accounts/

      *Note: Make sure you are logged into the SDK. Run ```gcloud auth login``` to connect to GCP.*

      When the upload has completed, confirm the file has been uploaded to the correct spot.
      
      ![alt text](https://community.phronesis.cloud/uploads/default/original/1X/172cb49c1d855dbb6ce56cfa589e5a15a4ec7940.png)
      
## Configure Snowflake

We are now ready to configure snowflake so we can ingest the dataset directly from GCS. Head on over to the Snowflake Console.

1. First thing we need to do is elevate the Snowflake role so we can create a database, schemas and table. Run the following command in worksheet to use the role Account Admin. You can highlight the code you want to run and when you select run it will only execute what was highlighted in the worksheet.
   ```
   use role accountadmin;
   ```

2. Now we can go ahead and create our database, warehouse and schema. The warehouse is the actual compute that will be used to execute queries against our data set. We don't need anything excessive for the queries we will run but imagine a large company that gets millions of calls against a dataset from various sources. Separate warehouses for each database or application can isolate traffic which improves resiliency.
   ```
   create database if not exists redditdb;
   create warehouse if not exists redditwh with warehouse_size = 'xsmall' auto_suspend = 60 
   initially_suspended = true;
   use schema redditdb.public;
   use database redditdb;
   ```

3. For our dataset to import properly we need to structure our table with the correct column names and data types. In order to determine the required columns I peaked at the csv and matched the names for my table.
    ```
    CREATE TABLE REDDIT_ACCOUNTS (
      id number,
      name varchar(100),
      created_utc number,
      updated_on number,
      comment_karma number,
      link_karma number
   )
   ```

4. Snowflake has a streamlined way for you to grant their GCP stack to your GCS bucket. The commands below will create a storage integration for GCS and it will generate a service account that we will add to our IAM.
    ```
   CREATE STORAGE INTEGRATION gcp_storage
      TYPE = EXTERNAL_STAGE
      STORAGE_PROVIDER = GCS
      ENABLED = TRUE
      STORAGE_ALLOWED_LOCATIONS = ('*');
   ```
    After the above completes, run the following to describe the integration we just created. This will 
    show the service account address that we are going to use in our own GCP environment.
    ```
   DESC STORAGE INTEGRATION gcp_storage;
   ```
   ![alt text](https://community.phronesis.cloud/uploads/default/original/1X/1f042ec477086c63a30bb16bb00629d0d0f6861d.png)

# Create/Assign an IAM Role

We will create a role with only the permissions required to get data from a storage account followed by assigning the role to the service account. 

1. Create a custom role that has the permissions required to access the dataset.

   - Log into the Google Cloud Platform Console as a project editor.
   - From the home dashboard, choose IAM & admin » Roles.
   - Click Create Role.
   - Enter a name, and description for the custom role.
   - Click Add Permissions.
   - Filter the list of permissions using the ***Storage Admin*** role and add the following from the list:
         - `storage.buckets.get`
         - `storage.objects.get`
         - `storage.objects.list`

2. Assign the custom role to the Snowflake service account.

   - Head over to Storage in the GCP console.
   - Select a bucket to configure for access.
   - Click SHOW INFO PANEL in the upper-right corner. The information panel for the bucket slides out.
   - In the Add members field, paste the service account we retrieved from Snowflake.
     ![alt text](https://community.phronesis.cloud/uploads/default/original/1X/d7b65a82a6f7c0db21f578bf9e7fc429fac19f2a.png)
   - Click save.

# Import the Dataset from GCS

1. All that is left is for us to grant the integration access to a Snowflake account. In our case we will use the builtin ***sysadmin*** role.
   ```
   grant usage on integration gcp_storage to sysadmin;
   use role sysadmin;
   ```

2. In order for the data to be processed properly, we need to specify how the data structured and also identify the type of compression so Snowflake can decompress the data.
   ```
   create or replace file format reddit_accounts_csv
      type = csv
      field_delimiter = ','
      skip_header = 1
      null_if = ('NULL', 'null')
      empty_field_as_null = true
      compression = gzip;
   ```

3. Create a Snowflake stage that puts together the file format and storage integration components.
   ```
   create stage my_gcs_stage
     url = 'gcs://reddit_accounts'
     storage_integration = gcp_storage
     file_format = reddit_accounts_csv;   
   ```

4. Finally, copy the data into the REDDIT_ACCOUNTS table using the stage created above.
   ```
   copy into REDDIT_ACCOUNTS
     from @my_gcs_stage
   ```
Looking at the query, it took 2 minutes and 12 seconds to import 69,382,538 rows into our table from a compressed csv file.
![image](https://user-images.githubusercontent.com/26353407/114261714-12924d00-99aa-11eb-99b8-8642e5811ec2.png)

# Querying the Data
Return all reddit usernames that contain greg in them.
```
SELECT * FROM REDDIT_ACCOUNTS
  WHERE NAME LIKE '%greg%'
```
<br/>

Return the sum of all reddit usernames that have "greg" in them.
```
SELECT COUNT(NAME) FROM REDDIT_ACCOUNTS
  WHERE NAME LIKE '%greg%'
```
| Row     | COUNT(NAME)    |
| :------------- | :---------- |
|  1 | 25350   |
<br/>

Return the sum of all reddit usernames that have "trump" in them.
```
SELECT COUNT(NAME) FROM REDDIT_ACCOUNTS
  WHERE NAME LIKE '%trump%'
```
| Row     | COUNT(NAME)    |
| :------------- | :---------- |
|  1 | 10643   |
<br/>

See who has the most comment karma out of 69 million user accounts. 
```
SELECT * FROM REDDIT_ACCOUNTS
  ORDER BY COMMENT_KARMA DESC
```

| Row     | NAME    | COMMENT_KARMA     |
| :------------- | :---------- | :-----------|
|  1 | TooShiftyForYou   | 13076606   |
| 2   | Poem_for_your_sprog | 4480894 |
| 3   | dick-nipples | 3747915 |
<br/>

## Reference
https://docs.snowflake.com/en/user-guide/data-load-gcs-config.html
