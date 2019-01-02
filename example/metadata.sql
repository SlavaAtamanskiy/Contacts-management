--------------------------------------------------------
--  File created - середа-січня-02-2019   
--------------------------------------------------------
--------------------------------------------------------
--  DDL for Sequence CLIENTS_SEQ1
--------------------------------------------------------

   CREATE SEQUENCE  "CLIENTS_SEQ1"  MINVALUE 1 MAXVALUE 9999999999999999999999999999 INCREMENT BY 1 START WITH 21 CACHE 20 NOORDER  NOCYCLE ;
--------------------------------------------------------
--  DDL for Sequence CONTACTS_CLIENTS_SEQ
--------------------------------------------------------

   CREATE SEQUENCE  "CONTACTS_CLIENTS_SEQ"  MINVALUE 1 MAXVALUE 9999999999999999999999999999 INCREMENT BY 1 START WITH 221 CACHE 20 NOORDER  NOCYCLE ;
--------------------------------------------------------
--  DDL for Table CLIENTS
--------------------------------------------------------

  CREATE TABLE "CLIENTS" 
   (	"ID" NUMBER, 
	"NAME" VARCHAR2(150)
   ) ;
--------------------------------------------------------
--  DDL for Table CONTACTS_CLIENTS
--------------------------------------------------------

  CREATE TABLE "CONTACTS_CLIENTS" 
   (	"ID" NUMBER, 
	"CONTACT" VARCHAR2(2500), 
	"PARENT" NUMBER, 
	"TYPE" VARCHAR2(30), 
	"VALUE" VARCHAR2(500)
   ) ;
--------------------------------------------------------
--  DDL for Index CLIENTS_PK
--------------------------------------------------------

  CREATE UNIQUE INDEX "CLIENTS_PK" ON "CLIENTS" ("ID") 
  ;
--------------------------------------------------------
--  DDL for Index CONTACTS_CLIENTS_PK
--------------------------------------------------------

  CREATE UNIQUE INDEX "CONTACTS_CLIENTS_PK" ON "CONTACTS_CLIENTS" ("ID") 
  ;
--------------------------------------------------------
--  DDL for Trigger BI_CLIENTS
--------------------------------------------------------

  CREATE OR REPLACE TRIGGER "BI_CLIENTS" 
  before insert on "CLIENTS"               
  for each row  
begin   
  if :NEW."ID" is null then 
    select "CLIENTS_SEQ1".nextval into :NEW."ID" from sys.dual; 
  end if; 
end; 

/
ALTER TRIGGER "BI_CLIENTS" ENABLE;
--------------------------------------------------------
--  DDL for Trigger BI_CLIENTS_AFTER_INSERT
--------------------------------------------------------

  CREATE OR REPLACE TRIGGER "BI_CLIENTS_AFTER_INSERT" 
  after insert on "CLIENTS"
  for each row
BEGIN
 contacts_management.insert_contacts('CLIENTS', CLIENTS_SEQ1.currval);
END;

/
ALTER TRIGGER "BI_CLIENTS_AFTER_INSERT" ENABLE;
--------------------------------------------------------
--  DDL for Trigger BI_CONTACTS_CLIENTS
--------------------------------------------------------

  CREATE OR REPLACE TRIGGER "BI_CONTACTS_CLIENTS" 
  before insert on "CONTACTS_CLIENTS"               
  for each row  
begin   
  if :NEW."ID" is null then 
    select "CONTACTS_CLIENTS_SEQ".nextval into :NEW."ID" from sys.dual; 
  end if; 
end;

/
ALTER TRIGGER "BI_CONTACTS_CLIENTS" ENABLE;

--------------------------------------------------------
--  DDL for Package CONTACTS_MANAGEMENT
--------------------------------------------------------

  CREATE OR REPLACE PACKAGE "CONTACTS_MANAGEMENT" as
   PROCEDURE insert_contacts (
       p_table_name IN VARCHAR2,
       p_sequence_val IN NUMBER);
   PROCEDURE delete_contacts (
       p_id IN NUMBER,
       p_table_name IN VARCHAR2);
   FUNCTION get_contacts  RETURN VARCHAR2;
   FUNCTION get_contact_view(
       p_id IN NUMBER,
       p_table_name IN VARCHAR2,
       p_type IN VARCHAR2) RETURN VARCHAR2;
   FUNCTION replace_forbidden_symbols (
       p_value IN VARCHAR2) RETURN VARCHAR2;
   PROCEDURE set_contacts_to_defaults;
   PROCEDURE update_contacts_state (
      p_type IN VARCHAR2,
      p_parent IN VARCHAR2,
      p_cnt IN VARCHAR2);
   FUNCTION add_contact (
      v_type IN VARCHAR2,
      v_parent IN VARCHAR2,
      cnt IN VARCHAR2,
      contacts IN VARCHAR2) RETURN CLOB;
   PROCEDURE on_page_load (
     p_id IN NUMBER,
     p_table_name IN VARCHAR2);
end CONTACTS_MANAGEMENT;


/

--------------------------------------------------------
--  DDL for Package Body CONTACTS_MANAGEMENT
--------------------------------------------------------

  CREATE OR REPLACE PACKAGE BODY "CONTACTS_MANAGEMENT" as

--CONTACTS_MANAGEMENT PACKAGE. S.Atamanskiy tasks 11.12.2018

-- PROGRAM INTERFACE

/******************************************************************************
-- procedure: insert_contacts
-- parameters: p_table_name => varachar2; parent table name;
--             p_sequence_name => varchar2; parent sequence name;
-- purpose: inserts values into child contacts table using global variable state;
******************************************************************************/
PROCEDURE insert_contacts (
    p_table_name IN VARCHAR2,
    p_sequence_val IN NUMBER)
  IS
       v_contacts VARCHAR2(2500) := contacts_management.get_contacts;
       v_json    apex_json.t_values;
       v_par     VARCHAR2(250) := '';
       v_count   int;
       v_key     VARCHAR2(250);
       v_val     VARCHAR2(250);
       json_members WWV_FLOW_T_VARCHAR2;
       table_name VARCHAR2(100);
       query_string VARCHAR2(4000);

  BEGIN

      table_name := 'CONTACTS_'||p_table_name;
      apex_json.parse(v_json, v_contacts);
      json_members := apex_json.get_members(p_path=>'.',p_values=>v_json);
      v_count := json_members.count;
      v_key   := json_members(v_count);
      v_par   := apex_json.get_varchar2(p_values => v_json, p_path => v_key, p0 => v_count);

      if UPPER(v_par) = 'UNDEFINED' Then
         RETURN;
      end if;

      FOR i IN 1 ..  v_count LOOP
            v_key  := json_members(i);
            v_val  := apex_json.get_varchar2(p_values => v_json, p_path => v_key, p0 => i);
            --skipping empty values
            if v_val is null or UPPER(v_val) = 'UNDEFINED' or UPPER(v_key) = 'TYPE' then
               CONTINUE;
             end if;

             query_string := 'INSERT INTO '|| table_name ||' (CONTACT, PARENT, TYPE, VALUE) VALUES (:v_contacts, :sequence_val, :v_key, :v_val)';
             dbms_output.put_line(query_string);
             EXECUTE IMMEDIATE query_string USING v_contacts, p_sequence_val, v_key, v_val;

         END LOOP;

END insert_contacts;

/******************************************************************************
-- procedure: delete_contacts
-- parameters: p_table_name => varachar2; parent table name;
--             p_id => varchar2; parent table id;
-- purpose: deletes data from child contacts table using foreign key field
******************************************************************************/
PROCEDURE delete_contacts (p_id IN NUMBER, p_table_name IN VARCHAR2)
  IS
  query_string VARCHAR2(250);
BEGIN

 query_string := 'DELETE FROM CONTACTS_'|| p_table_name ||' WHERE PARENT = :p_id';
 EXECUTE IMMEDIATE query_string USING p_id;

END;
/******************************************************************************
-- procedure: update_contacts_state
-- parameters: v_type => varachar2; purpose: identifies type of a contact, string: "legal_adress", "physical_adress", "phone", "email";
--             parent => varchar2; name of a parent table to which contact information refers;
--             cnt    => varchar2; contact to be saved;
-- purpose: updates contacts in aplication global variable on contact change;
******************************************************************************/

PROCEDURE update_contacts_state(
       p_type IN VARCHAR2,
       p_parent IN VARCHAR2,
       p_cnt IN VARCHAR2)
 IS

  v_contacts varchar2(2500) := APEX_UTIL.get_session_state(p_item => 'CONTACTS');  --c_contacts CLOB;
  v_contact varchar2(500) := replace_forbidden_symbols(p_value => p_cnt);

BEGIN
  --c_contacts := contacts_management.add_contact(v_type=>p_type,  v_parent =>p_parent, cnt=> p_cnt, contacts=> v_contacts);  --v_contacts := CAST(c_contacts AS VARCHAR2);
  v_contacts := contacts_management.add_contact(v_type=>p_type,  v_parent =>p_parent, cnt=> v_contact, contacts=> v_contacts);
  APEX_UTIL.set_session_state(p_name => 'CONTACTS', p_value => v_contacts);

END update_contacts_state;

/******************************************************************************
-- procedure: on_page_load
parameters:
--         p_id => Number; foreign key id to find information in child table
--         p_table_name => varchar2; parent table name
-- purpose: updates contacts in aplication global variable on page load;
******************************************************************************/

PROCEDURE on_page_load (
       p_id IN NUMBER,
       p_table_name IN VARCHAR2)
 IS

  v_contacts varchar2(2500);
  query_string varchar2(150);
  prefix varchar2(10):= 'CONTACTS_';

BEGIN

  if p_id is null then
     set_contacts_to_defaults;
  else
     query_string:= 'SELECT CONTACT FROM (SELECT CONTACT FROM '|| prefix || p_table_name ||' WHERE PARENT = :p_id) WHERE ROWNUM <=1';
     EXECUTE IMMEDIATE query_string INTO v_contacts USING p_id;
     APEX_UTIL.set_session_state(p_name => 'CONTACTS', p_value => v_contacts);
  end if;

EXCEPTION
  WHEN NO_DATA_FOUND THEN
   set_contacts_to_defaults;

END on_page_load;

/******************************************************************************
-- function: get_contact_view
-- parameters: -- p_id => Number; foreign key id to find information in child table
--                p_table_name => varchar2; parent table name
--                p_type   => varachar2; purpose: identifies type of a contact, string: "legal_address", "physical_address", "phone", "email";
-- purpose: invoked  in contacts fieldes as a source to dynamically retrieve contacts;
******************************************************************************/
FUNCTION get_contact_view(
       p_id IN NUMBER,
       p_table_name IN VARCHAR2,
       p_type IN VARCHAR2) RETURN VARCHAR2 IS

  v_contacts varchar2(2500);
  query_string varchar2(150);
  res varchar2(500);
  prefix varchar2(10):= 'CONTACTS_';

BEGIN

  if p_id is null then
     return null;
  else
     query_string:= 'SELECT CONTACT FROM '|| prefix || p_table_name ||' WHERE PARENT = :p_id  AND TYPE = :p_type';
     EXECUTE IMMEDIATE query_string INTO v_contacts USING p_id, p_type;
     apex_json.parse(v_contacts);
     res := apex_json.get_varchar2(p_path => p_type);
     return res;
  end if;

EXCEPTION
  WHEN NO_DATA_FOUND THEN

   return null;

END get_contact_view;

 -- END PROGRAM INTERFACE

 -- OTHER PROCEDURES AND FUNCTIONS

 /******************************************************************************
-- procedure: set_contacts_to_defaults
-- purpose: clears the aplication variable of data from previous operations;
******************************************************************************/
PROCEDURE set_contacts_to_defaults
  IS
      contacts VARCHAR2(2500) := '{ "legal_address": "",  "physical_address": "",   "phone": "", "email": "",  "type": "undefined" }';
  BEGIN

     APEX_UTIL.set_session_state(p_name => 'CONTACTS', p_value => contacts);

 END set_contacts_to_defaults;

/******************************************************************************
-- function: add_contact
-- parameters: v_type   => varachar2; purpose: identifies type of a contact, string: "legal_address", "physical_address", "phone", "email";
--             parent   => varchar2; name of a parent table to which contact information refers;
--             cnt      => varchar2; contact to be saved in contact state;
--             contacts => varchar2; current state of contacts;
******************************************************************************/

FUNCTION add_contact (
       v_type IN VARCHAR2,
       v_parent IN VARCHAR2,
       cnt IN VARCHAR2,
       contacts IN VARCHAR2) RETURN CLOB
  IS
       v_contacts VARCHAR2(2500) := contacts;
       v_json    apex_json.t_values;
       v_par     VARCHAR2(250) := '';
       v_count   int;
       v_key     VARCHAR2(250);
       v_val     VARCHAR2(250);
       json_members WWV_FLOW_T_VARCHAR2;

  BEGIN

      --apex_json.initialize_clob_output;
      apex_json.parse(v_json, v_contacts);

      json_members := apex_json.get_members(p_path=>'.',p_values=>v_json);
      v_count := json_members.count;
      v_key   := json_members(v_count);
      v_par   := apex_json.get_varchar2(p_values => v_json, p_path => v_key, p0 => v_count);
      --dbms_output.put_line(v_par);

      if UPPER(v_par) = 'UNDEFINED' or UPPER(v_par) = UPPER(v_parent) Then

         v_contacts := '{';
         FOR i IN 1 ..  v_count LOOP
            v_key  := json_members(i);
            v_val  := apex_json.get_varchar2(p_values => v_json, p_path => v_key, p0 => i);
            --overriding empty values
            if v_val is null or UPPER(v_val) = 'UNDEFINED' then
               v_val := '';
             end if;
             --overriding same type
             if UPPER(v_key) = UPPER(v_type) then
                v_val := cnt;
             end if;
             --overriding parente
             if UPPER(v_key) = UPPER('type') then
                if UPPER(v_par) = 'UNDEFINED' then
                   v_val := v_parent;
                end if;
             end if;
             v_contacts := v_contacts || '"' || v_key || '":"' || v_val ||'"';
             if i <> v_count then
                v_contacts := v_contacts || ',';
             end if;
         END LOOP;
         v_contacts := v_contacts || '}';

         RETURN v_contacts;

      else

         set_contacts_to_defaults;
         v_contacts := get_contacts;
         RETURN add_contact(v_type, v_parent, cnt, v_contacts);

      end if;

END add_contact;

/******************************************************************************
-- function: replace_forbidden_symbols
-- parameters: p_value  => varachar2; value of a contact that is being edited;
--             purpose: replaces forbidden symbols to avoid errors while pl/sql code is being executed;
--             known errors:
--             "\" - Ajax call returned server error ORA-20987: Error at line 1, col 73: strict mode JSON parser does not allow unquoted literals for Execute PL/SQL Code.
******************************************************************************/

FUNCTION replace_forbidden_symbols (
       p_value IN VARCHAR2) RETURN VARCHAR2
 IS

v_specialSymbols varchar2(50) := q'#\'"#';
v_symb varchar2(1);
i int := 0;
v_result varchar2(500):= p_value;

BEGIN

    WHILE i <= length(v_specialSymbols) LOOP

           v_symb := SUBSTR(v_specialSymbols, i, 1);
           if INSTR(v_result, v_symb) > 0 and INSTR(v_specialSymbols, v_symb) > 0 then
               v_result := REPLACE(v_result, v_symb, ' ');
               --dbms_output.put_line(v_result);
           end if;
           i:= i+1;

    END LOOP;

   v_result:= ''||v_result||'';

   return v_result;

END replace_forbidden_symbols;


/******************************************************************************
-- function: get_contacts
-- parameters:
-- return value: varchar2 || JSON string with current contacts || purpose : transferring unsaved contacts from forms into db trigger using application variable || || author 2018 : Atamanskiy S.
******************************************************************************/

FUNCTION get_contacts
return VARCHAR2
is

v_res varchar2(2500) := '';

begin

    v_res := APEX_UTIL.GET_SESSION_STATE ('CONTACTS');
    return v_res;

END get_contacts;

end CONTACTS_MANAGEMENT;


/

--------------------------------------------------------
--  Constraints for Table CLIENTS
--------------------------------------------------------

  ALTER TABLE "CLIENTS" ADD CONSTRAINT "CLIENTS_PK" PRIMARY KEY ("ID") ENABLE;
--------------------------------------------------------
--  Constraints for Table CONTACTS_CLIENTS
--------------------------------------------------------

  ALTER TABLE "CONTACTS_CLIENTS" ADD CONSTRAINT "CONTACTS_CLIENTS_PK" PRIMARY KEY ("ID") ENABLE;
--------------------------------------------------------
--  Ref Constraints for Table CONTACTS_CLIENTS
--------------------------------------------------------

  ALTER TABLE "CONTACTS_CLIENTS" ADD CONSTRAINT "CONTACTS_CLIENTS_FK" FOREIGN KEY ("PARENT")
	  REFERENCES "CLIENTS" ("ID") ON DELETE CASCADE ENABLE;
