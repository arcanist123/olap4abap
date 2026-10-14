*----------------------------------------------------------------------------------------------------------------------*
* olap4abap - XMLA server with an MDX engine for SAP BW               https://github.com/arcanist123/olap4abap
* Copyright (c) 2026 the olap4abap authors
*
* This program and the accompanying materials are made available under the terms of the Eclipse Public License 2.0,
* which is available at https://www.eclipse.org/legal/epl-2.0/
* SPDX-License-Identifier: EPL-2.0
*
* olap4abap contains code derived from Mondrian (Eclipse Public License 1.0): Copyright (C) 1998-2005 Julian Hyde,
* Copyright (C) 2005-2021 Hitachi Vantara and others, Copyright (C) 2021-2025 Sergei Semenkov. See the NOTICE file.
*----------------------------------------------------------------------------------------------------------------------*
"! The trace of the XMLA endpoint (ZZXXMLA1_MAIN_ENDPOINT), switched on per user: table ZZXXMLA1_TRCUSR holds the
"! users whose calls are traced, table ZZXXMLA1_TRACE a row per call of such a user (sy-uname, the logon of the ICF
"! node: while the node logs on anonymously every caller is its service user, told apart by the client's address and
"! User-Agent). A row has the SOAP request, what it asks (Discover and its rowset, Execute and its MDX statement), the
"! HTTP status, whether the answer is a SOAP fault, the runtime, the SOAP response, gzipped (Excel's grids are
"! megabytes of XML), and the SQL statements the call ran with their rows, time and error (ZZXXMLA1_CL_SQL's
"! statement_log, gzipped XML; the first c_sql_kept of them), each with the phase and the node of the query that ran
"! it, and the explanation of the query (ZZXXMLA1_CL_MDX_EXPLAIN: its resolved tree, in the same XML). The row is written and committed before the call is handled, so a call that dumps is in the
"! trace too, with status 0 and no response; the answer is added when it is there. A trace switches itself off
"! c_active_hours after it was switched on (switching it on again starts the hours anew). A caller can also ask for
"! the trace of one call whatever the user's trace (the MDX console does, to show the call's SQL statements: start
"! with forced). Whenever a trace is switched
"! on, the calls older than c_retention_days and the switched-off users' rows are deleted. The trace page (web/schema/trace.js) reads and switches the trace through
"! the schema API (GET trace, ...).
CLASS zzxxmla1_cl_trace DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    "! how long a traced call is kept
    CONSTANTS c_retention_days TYPE i VALUE 7.
    "! how long a trace stays on after it was switched on
    CONSTANTS c_active_hours TYPE i VALUE 2.
    "! how many of the SQL statements of a call are kept
    CONSTANTS c_sql_kept TYPE i VALUE 10000.
    "! a response in UTF-8 parts (ZZXXMLA1_CL_XMLA_MDDATASET's answer)
    TYPES ty_t_part TYPE STANDARD TABLE OF xstring WITH EMPTY KEY.
    TYPES:
      "! a user with the trace on: since when, who switched it on and until when it is on
      BEGIN OF ty_user,
        user_name    TYPE syuname,
        changed_at   TYPE timestampl,  " UTC
        changed_by   TYPE syuname,
        active_until TYPE timestampl,  " UTC
      END OF ty_user,
      ty_t_user TYPE STANDARD TABLE OF ty_user WITH EMPTY KEY.
    TYPES:
      "! what a SOAP request asks: DISCOVER or EXECUTE (initial if it is no XMLA request), the rowset of a Discover,
      "! the statement of an Execute
      BEGIN OF ty_call,
        xmla_method  TYPE string,
        request_type TYPE string,
        mdx          TYPE string,
      END OF ty_call.
    TYPES:
      "! a traced call without its request and response
      BEGIN OF ty_entry,
        trace_id        TYPE sysuuid_c32,
        user_name       TYPE syuname,
        created_at      TYPE timestampl,  " UTC, when the call came in
        xmla_method     TYPE string,
        request_type    TYPE string,
        status          TYPE i,           " HTTP status; 0 while the call runs or if it was aborted
        fault           TYPE abap_bool,   " the answer is a SOAP fault
        runtime_ms      TYPE i,
        client_address  TYPE string,
        user_agent      TYPE string,
        request_length  TYPE i,           " characters
        response_length TYPE i,           " characters, before it was gzipped
        sql_count       TYPE i,           " the SQL statements the call ran (ZZXXMLA1_CL_SQL)
        sql_ms          TYPE i,           " their time
        mdx             TYPE string,
      END OF ty_entry,
      ty_t_entry TYPE STANDARD TABLE OF ty_entry WITH EMPTY KEY.
    TYPES:
      "! a SQL statement a call ran (ZZXXMLA1_CL_SQL=>ty_logged): its rows, its time, the error it failed with, and
      "! the phase and the node of the query's explanation that ran it (0: none)
      BEGIN OF ty_statement,
        sql   TYPE string,
        rows  TYPE i,
        time  TYPE int8,          " microseconds
        error TYPE string,
        phase TYPE string,
        node  TYPE i,
      END OF ty_statement,
      ty_t_statement TYPE STANDARD TABLE OF ty_statement WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_detail,
        entry    TYPE ty_entry,
        request  TYPE string,
        response TYPE string,
        "! the SQL statements in the order they ran (the first c_sql_kept)
        sql      TYPE ty_t_statement,
        "! the explanation of the executed query (JSON, ZZXXMLA1_CL_MDX_EXPLAIN); empty if there is none
        explain  TYPE string,
      END OF ty_detail.

    "! Whether the calls of a user are traced: the trace was switched on less than c_active_hours ago.
    CLASS-METHODS is_active
      IMPORTING user_name     TYPE syuname
      RETURNING VALUE(result) TYPE abap_bool.
    "! The users with the trace on, by name; not those whose c_active_hours are over.
    CLASS-METHODS users
      RETURNING VALUE(result) TYPE ty_t_user.
    "! Switches the trace on for a user for c_active_hours from now, by the current user, and deletes the expired
    "! rows (delete_expired); the caller commits.
    CLASS-METHODS activate
      IMPORTING user_name TYPE syuname.
    "! Switches the trace off for a user (its traced calls stay); the caller commits.
    CLASS-METHODS deactivate
      IMPORTING user_name TYPE syuname.
    "! Starts the trace of a call if the current user's calls are traced: its row is written and committed at once.
    "! @parameter request | the SOAP request
    "! @parameter forced | the call is traced even if the user's trace is off (the caller asked for it)
    "! @parameter result | the trace of the call, to finish when the answer is there; not bound if the trace is off
    CLASS-METHODS start
      IMPORTING request        TYPE string
                client_address TYPE string
                user_agent     TYPE string
                forced         TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(result)  TYPE REF TO zzxxmla1_cl_trace.
    "! The traced calls, newest first, without request and response.
    "! @parameter user_name | only this user's; initial: everyone's
    "! @parameter xmla_method | only calls of this method (DISCOVER or EXECUTE); initial: all calls
    "! @parameter max | at most this many
    CLASS-METHODS list
      IMPORTING user_name     TYPE syuname OPTIONAL
                xmla_method   TYPE string OPTIONAL
                !max          TYPE i DEFAULT 200
      RETURNING VALUE(result) TYPE ty_t_entry.
    "! A traced call with its request, its response and its SQL statements, unzipped; its trace_id is initial if
    "! there is none.
    CLASS-METHODS read
      IMPORTING trace_id      TYPE sysuuid_c32
      RETURNING VALUE(result) TYPE ty_detail.
    "! Deletes the traced calls of a user (initial: of everyone); the caller commits.
    "! @parameter result | how many were deleted
    CLASS-METHODS clear
      IMPORTING user_name     TYPE syuname OPTIONAL
      RETURNING VALUE(result) TYPE i.
    "! What a SOAP request asks (ZZXXMLA1_CL_XMLA_REQUEST); all initial if it is no XMLA request.
    CLASS-METHODS describe
      IMPORTING request       TYPE string
      RETURNING VALUE(result) TYPE ty_call.

    "! the call's row in ZZXXMLA1_TRACE (GET trace/entry?id=...)
    DATA trace_id TYPE sysuuid_c32 READ-ONLY.

    "! Adds the answer to the call's row, with the SQL statements run since start, their time and the statements
    "! themselves, and commits.
    "! @parameter status | the HTTP status
    "! @parameter response | the SOAP response
    "! @parameter parts | instead of response: the SOAP response in UTF-8 parts (an Execute's answer)
    METHODS finish
      IMPORTING status   TYPE i
                response TYPE string OPTIONAL
                parts    TYPE ty_t_part OPTIONAL.
  PROTECTED SECTION.
  PRIVATE SECTION.
    "! the length of the column USER_AGENT
    CONSTANTS c_user_agent_length TYPE i VALUE 255.
    "! GET RUN TIME when the call came in (microseconds)
    DATA started TYPE i.

    "! Deletes the calls older than c_retention_days and the users whose c_active_hours are over.
    CLASS-METHODS delete_expired
      IMPORTING now TYPE timestampl.
    "! The time stamp that many seconds before another.
    CLASS-METHODS seconds_before
      IMPORTING tstmp         TYPE timestampl
                seconds       TYPE i
      RETURNING VALUE(result) TYPE timestampl.
    "! Until when a trace switched on at that time is on.
    CLASS-METHODS active_until
      IMPORTING changed_at    TYPE timestampl
      RETURNING VALUE(result) TYPE timestampl.
    "! The text gzipped as UTF-8; empty for an empty text or if it cannot be compressed.
    CLASS-METHODS compress
      IMPORTING !text         TYPE string
      RETURNING VALUE(result) TYPE xstring.
    "! UTF-8 gzipped, as compress gives a text; empty for empty data or if it cannot be compressed.
    CLASS-METHODS compress_utf8
      IMPORTING !data         TYPE xstring
      RETURNING VALUE(result) TYPE xstring.
    "! The text of gzipped UTF-8; empty for empty data or if it cannot be unzipped.
    CLASS-METHODS decompress
      IMPORTING !data         TYPE xstring
      RETURNING VALUE(result) TYPE string.
    "! The statements (the first c_sql_kept) and the explanation as gzipped XML; empty for neither.
    CLASS-METHODS serialize_sql
      IMPORTING statements    TYPE ty_t_statement
                explain       TYPE string
      RETURNING VALUE(result) TYPE xstring.
    "! The statements and the explanation of serialize_sql; none for empty data or data that cannot be read.
    CLASS-METHODS deserialize_sql
      IMPORTING !data      TYPE xstring
      EXPORTING statements TYPE ty_t_statement
                explain    TYPE string.
    "! Whether a SOAP response is a fault.
    CLASS-METHODS is_fault
      IMPORTING response      TYPE string
      RETURNING VALUE(result) TYPE abap_bool.
ENDCLASS.



CLASS zzxxmla1_cl_trace IMPLEMENTATION.

  METHOD is_active.
    SELECT SINGLE changed_at FROM zzxxmla1_trcusr
      WHERE user_name = @user_name
      INTO @DATA(changed_at).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    GET TIME STAMP FIELD DATA(now).
    result = xsdbool( active_until( changed_at ) > now ).
  ENDMETHOD.

  METHOD users.
    SELECT user_name, changed_at, changed_by FROM zzxxmla1_trcusr
      ORDER BY user_name ASCENDING
      INTO CORRESPONDING FIELDS OF TABLE @result.
    GET TIME STAMP FIELD DATA(now).
    LOOP AT result REFERENCE INTO DATA(user).
      user->active_until = active_until( user->changed_at ).
    ENDLOOP.
    " expired, but not deleted yet: that happens when a trace is switched on
    DELETE result WHERE active_until <= now.
  ENDMETHOD.

  METHOD activate.
    DATA row TYPE zzxxmla1_trcusr.
    row-user_name = user_name.
    row-changed_by = sy-uname.
    GET TIME STAMP FIELD row-changed_at.
    delete_expired( row-changed_at ).
    MODIFY zzxxmla1_trcusr FROM @row.
  ENDMETHOD.

  METHOD deactivate.
    DELETE FROM zzxxmla1_trcusr WHERE user_name = @user_name.
  ENDMETHOD.

  METHOD start.
    IF forced = abap_false AND is_active( sy-uname ) = abap_false.
      RETURN.
    ENDIF.
    DATA row TYPE zzxxmla1_trace.
    TRY.
        row-trace_id = cl_system_uuid=>create_uuid_c32_static( ).
      CATCH cx_uuid_error.
        RETURN.
    ENDTRY.
    result = NEW #( ).
    result->trace_id = row-trace_id.
    GET RUN TIME FIELD result->started.
    zzxxmla1_cl_sql=>reset_statistics( ).
    zzxxmla1_cl_sql=>log_statements = abap_true.
    zzxxmla1_cl_mdx_explain=>clear( ).
    DATA(call) = describe( request ).
    row-user_name = sy-uname.
    row-xmla_method = call-xmla_method.
    row-request_type = call-request_type.
    row-mdx = call-mdx.
    row-client_address = client_address.
    row-user_agent = substring( val = user_agent len = nmin( val1 = strlen( user_agent ) val2 = c_user_agent_length ) ).
    row-request_length = strlen( request ).
    row-request = request.
    GET TIME STAMP FIELD row-created_at.
    INSERT zzxxmla1_trace FROM @row.
    " committed before the call is handled: a call that dumps stays in the trace
    COMMIT WORK.
  ENDMETHOD.

  METHOD finish.
    GET RUN TIME FIELD DATA(now).
    DATA(runtime_ms) = ( now - started ) DIV 1000.
    IF parts IS INITIAL.
      DATA(fault) = is_fault( response ).
      DATA(response_length) = strlen( response ).
      DATA(zipped) = compress( response ).
    ELSE.
      " an Execute's answer has no fault (a fault is a text); its length is in bytes, the same for ASCII
      DATA(bytes) = VALUE xstring( ).
      LOOP AT parts INTO DATA(part).
        CONCATENATE bytes part INTO bytes IN BYTE MODE.
      ENDLOOP.
      response_length = xstrlen( bytes ).
      zipped = compress_utf8( bytes ).
    ENDIF.
    DATA(sql_count) = zzxxmla1_cl_sql=>statement_count.
    DATA(sql_ms) = CONV i( zzxxmla1_cl_sql=>statement_time DIV 1000 ).
    DATA(sql_log) = serialize_sql( statements = CORRESPONDING #( zzxxmla1_cl_sql=>statement_log )
                                   explain    = zzxxmla1_cl_mdx_explain=>last ).
    zzxxmla1_cl_sql=>log_statements = abap_false.
    zzxxmla1_cl_mdx_explain=>clear( ).
    UPDATE zzxxmla1_trace
      SET status          = @status,
          fault           = @fault,
          runtime_ms      = @runtime_ms,
          response_length = @response_length,
          sql_count       = @sql_count,
          sql_ms          = @sql_ms,
          response        = @zipped,
          sql_log         = @sql_log
      WHERE trace_id = @trace_id.
    COMMIT WORK.
  ENDMETHOD.

  METHOD list.
    DATA users TYPE RANGE OF syuname.
    IF user_name IS NOT INITIAL.
      users = VALUE #( ( sign = 'I' option = 'EQ' low = user_name ) ).
    ENDIF.
    DATA methods TYPE RANGE OF zzxxmla1_trace-xmla_method.
    IF xmla_method IS NOT INITIAL.
      methods = VALUE #( ( sign = 'I' option = 'EQ' low = xmla_method ) ).
    ENDIF.
    SELECT trace_id, user_name, created_at, xmla_method, request_type, status, fault, runtime_ms, client_address,
           user_agent, request_length, response_length, sql_count, sql_ms, mdx
      FROM zzxxmla1_trace
      WHERE user_name IN @users
        AND xmla_method IN @methods
      ORDER BY created_at DESCENDING
      INTO CORRESPONDING FIELDS OF TABLE @result
      UP TO @max ROWS.
  ENDMETHOD.

  METHOD read.
    SELECT SINGLE * FROM zzxxmla1_trace
      WHERE trace_id = @trace_id
      INTO @DATA(row).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    result-entry = CORRESPONDING #( row ).
    result-request = row-request.
    result-response = decompress( row-response ).
    deserialize_sql( EXPORTING data       = row-sql_log
                     IMPORTING statements = result-sql
                               explain    = result-explain ).
  ENDMETHOD.

  METHOD clear.
    DATA users TYPE RANGE OF syuname.
    IF user_name IS NOT INITIAL.
      users = VALUE #( ( sign = 'I' option = 'EQ' low = user_name ) ).
    ENDIF.
    DELETE FROM zzxxmla1_trace WHERE user_name IN @users.
    result = sy-dbcnt.
  ENDMETHOD.

  METHOD describe.
    TRY.
        DATA(parsed) = zzxxmla1_cl_xmla_request=>parse( request ).
      CATCH zzxxmla1_cx_xmla.
        " not XML, not SOAP or not XMLA: the trace shows the request and the fault it got
        RETURN.
    ENDTRY.
    result = VALUE #( xmla_method  = parsed-method
                      request_type = parsed-type
                      mdx          = parsed-statement ).
  ENDMETHOD.

  METHOD delete_expired.
    DATA(oldest) = seconds_before( tstmp = now seconds = c_retention_days * 86400 ).
    DELETE FROM zzxxmla1_trace WHERE created_at < @oldest.
    DATA(switched_on) = seconds_before( tstmp = now seconds = c_active_hours * 3600 ).
    DELETE FROM zzxxmla1_trcusr WHERE changed_at <= @switched_on.
  ENDMETHOD.

  METHOD seconds_before.
    " whole seconds: the trace needs no finer limit
    result = cl_abap_tstmp=>subtractsecs( tstmp = CONV timestamp( tstmp ) secs = seconds ) ##TYPE.
  ENDMETHOD.

  METHOD active_until.
    result = cl_abap_tstmp=>add( tstmp = changed_at secs = c_active_hours * 3600 ).
  ENDMETHOD.

  METHOD compress.
    IF text IS INITIAL.
      RETURN.
    ENDIF.
    TRY.
        cl_abap_gzip=>compress_text( EXPORTING text_in    = text
                                               conversion = 'UTF-8'
                                     IMPORTING gzip_out   = result ).
      CATCH cx_parameter_invalid_range cx_sy_buffer_overflow cx_sy_conversion_codepage cx_sy_compression_error.
        CLEAR result.
    ENDTRY.
  ENDMETHOD.

  METHOD compress_utf8.
    IF data IS INITIAL.
      RETURN.
    ENDIF.
    TRY.
        cl_abap_gzip=>compress_binary( EXPORTING raw_in   = data
                                       IMPORTING gzip_out = result ).
      CATCH cx_parameter_invalid_range cx_sy_buffer_overflow cx_sy_compression_error.
        CLEAR result.
    ENDTRY.
  ENDMETHOD.

  METHOD decompress.
    IF data IS INITIAL.
      RETURN.
    ENDIF.
    TRY.
        cl_abap_gzip=>decompress_text( EXPORTING gzip_in    = data
                                                 conversion = 'UTF-8'
                                       IMPORTING text_out   = result ).
      CATCH cx_parameter_invalid_range cx_sy_buffer_overflow cx_sy_conversion_codepage cx_sy_compression_error.
        CLEAR result.
    ENDTRY.
  ENDMETHOD.

  METHOD serialize_sql.
    IF statements IS INITIAL AND explain IS INITIAL.
      RETURN.
    ENDIF.
    DATA(kept) = statements.
    IF lines( kept ) > c_sql_kept.
      DELETE kept FROM c_sql_kept + 1.
    ENDIF.
    DATA xml TYPE string.
    TRY.
        CALL TRANSFORMATION id SOURCE sql = kept explain = explain RESULT XML xml.
      CATCH cx_transformation_error.
        RETURN.
    ENDTRY.
    result = compress( xml ).
  ENDMETHOD.

  METHOD deserialize_sql.
    CLEAR: statements, explain.
    DATA(xml) = decompress( data ).
    IF xml IS INITIAL.
      RETURN.
    ENDIF.
    " a call traced before the explanation was kept has none in its XML
    TRY.
        CALL TRANSFORMATION id SOURCE XML xml RESULT sql = statements explain = explain.
      CATCH cx_transformation_error.
        CLEAR: statements, explain.
    ENDTRY.
  ENDMETHOD.

  METHOD is_fault.
    " the faults of ZZXXMLA1_CL_XMLA_HANDLER=>FAULT_RESULT; an error in a cell of an Execute is no fault
    result = xsdbool( find( val = response sub = `<SOAP-ENV:Fault>` ) >= 0 ).
  ENDMETHOD.

ENDCLASS.
