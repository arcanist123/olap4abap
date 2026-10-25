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
CLASS ltc_bw_mdx_api DEFINITION DEFERRED.
CLASS zzxxmla1_cl_bw_mdx_api DEFINITION LOCAL FRIENDS ltc_bw_mdx_api.

"! The endpoint's paths, bodies and answers; the resolution in BW's names on the clinic demo's aDSO (catalog and cube
"! ZCLVISITA) with one of the probe's statements (reference/auth/statements.json).
CLASS ltc_bw_mdx_api DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    CONSTANTS c_statement TYPE string
      VALUE `SELECT {[Measures].[ZCLVISNO]} ON 0 FROM [$ZCLVISITA] WHERE ([ZCLDOC].[001], [ZCLDIAG].[A09])`.
    METHODS paths FOR TESTING.
    METHODS plain_statement FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS execute_statement FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS discover_refused FOR TESTING.
    METHODS resolved FOR TESTING.
    METHODS unknown_name FOR TESTING.
    METHODS no_resource FOR TESTING.
    METHODS other_user_refused FOR TESTING.
    METHODS describe_defaults FOR TESTING.
    METHODS describe_given FOR TESTING.
    METHODS with_sql FOR TESTING.
ENDCLASS.

CLASS ltc_bw_mdx_api IMPLEMENTATION.

  METHOD paths.
    cl_abap_unit_assert=>assert_true( zzxxmla1_cl_bw_mdx_api=>is_api( `/bw` ) ).
    cl_abap_unit_assert=>assert_true( zzxxmla1_cl_bw_mdx_api=>is_api( `/bw/check` ) ).
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_bw_mdx_api=>is_api( `/bwx` ) ).
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_bw_mdx_api=>is_api( `/schema/api/auth/check` ) ).
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_bw_mdx_api=>is_api( `` ) ).
  ENDMETHOD.

  METHOD plain_statement.
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_bw_mdx_api=>statement_of( c_statement ) exp = c_statement ).
  ENDMETHOD.

  METHOD execute_statement.
    DATA(body) = |<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/"><SOAP-ENV:Body>| &&
                 |<Execute xmlns="urn:schemas-microsoft-com:xml-analysis"><Command><Statement>{ c_statement }| &&
                 |</Statement></Command><Properties><PropertyList><Catalog>$ZCLVISITA</Catalog></PropertyList>| &&
                 |</Properties></Execute></SOAP-ENV:Body></SOAP-ENV:Envelope>|.
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_bw_mdx_api=>statement_of( body ) exp = c_statement ).
  ENDMETHOD.

  METHOD discover_refused.
    DATA(body) = |<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/"><SOAP-ENV:Body>| &&
                 |<Discover xmlns="urn:schemas-microsoft-com:xml-analysis"><RequestType>DISCOVER_DATASOURCES| &&
                 |</RequestType><Restrictions><RestrictionList/></Restrictions><Properties><PropertyList/>| &&
                 |</Properties></Discover></SOAP-ENV:Body></SOAP-ENV:Envelope>|.
    TRY.
        zzxxmla1_cl_bw_mdx_api=>statement_of( body ).
        cl_abap_unit_assert=>fail( `no error` ).
      CATCH zzxxmla1_cx_xmla INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( act = error->description
                                            exp = `The body is an XMLA DISCOVER, not an Execute` ).
    ENDTRY.
  ENDMETHOD.

  METHOD resolved.
    DATA(result) = NEW zzxxmla1_cl_bw_mdx_api( )->handle( VALUE #( method = `POST` path = `/bw/check`
                                                                  body   = c_statement ) ).
    cl_abap_unit_assert=>assert_equals( act = result-status exp = 200 ).
    cl_abap_unit_assert=>assert_char_cp( act = result-body exp = `*"status":"RESOLVED"*` ).
    cl_abap_unit_assert=>assert_char_cp( act = result-body exp = `*"keyDate":"9999-12-31"*` ).
    " the members in olap4abap's names
    cl_abap_unit_assert=>assert_char_cp( act = result-body exp = `*"resolved":"*[ZCLDOC].[001]*[ZCLDIAG].[A09]*` ).
    cl_abap_unit_assert=>assert_false( result-failed ).
    " the statements only with sql=true
    cl_abap_unit_assert=>assert_char_np( act = result-body exp = `*"sql":*` ).
  ENDMETHOD.

  METHOD unknown_name.
    DATA(result) = NEW zzxxmla1_cl_bw_mdx_api( )->handle(
                     VALUE #( method = `POST` path = `/bw/check`
                              body   = `SELECT {[Measures].[ZCLVISNO]} ON 0 FROM [$ZCLVISITA] WHERE ([ZCLDOC].[999])` ) ).
    cl_abap_unit_assert=>assert_equals( act = result-status exp = 200 ).
    cl_abap_unit_assert=>assert_char_cp( act = result-body exp = `*"status":"ERROR"*not found*` ).
    cl_abap_unit_assert=>assert_true( result-failed ).
  ENDMETHOD.

  METHOD no_resource.
    DATA(api) = NEW zzxxmla1_cl_bw_mdx_api( ).
    cl_abap_unit_assert=>assert_equals( act = api->handle( VALUE #( method = `POST` path = `/bw/nowhere` ) )-status
                                        exp = 404 ).
    DATA(result) = api->handle( VALUE #( method = `GET` path = `/bw/check` ) ).
    cl_abap_unit_assert=>assert_equals( act = result-status exp = 405 ).
    cl_abap_unit_assert=>assert_equals( act = result-allow exp = `POST` ).
  ENDMETHOD.

  METHOD other_user_refused.
    DATA(result) = NEW zzxxmla1_cl_bw_mdx_api( )->handle(
                     VALUE #( method     = `POST` path = `/bw/check` body = c_statement
                              parameters = VALUE #( ( name = `user` value = `DDIC` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = result-status exp = 403 ).
  ENDMETHOD.

  METHOD describe_defaults.
    DATA(call) = zzxxmla1_cl_bw_mdx_api=>describe( VALUE #( method = `POST` path = `/bw/check` body = c_statement ) ).
    cl_abap_unit_assert=>assert_equals( act = call-xmla_method exp = `CHECK` ).
    cl_abap_unit_assert=>assert_equals( act = call-request_type exp = |{ sy-uname } 9999-12-31| ).
    cl_abap_unit_assert=>assert_equals( act = call-mdx exp = c_statement ).
  ENDMETHOD.

  METHOD describe_given.
    " as given, even where the check refuses them: the trace shows what was asked
    DATA(call) = zzxxmla1_cl_bw_mdx_api=>describe(
                   VALUE #( method     = `POST` path = `/bw/check` body = `<no XMLA`
                            parameters = VALUE #( ( name = `user` value = `zzxxmla1_a01` )
                                                  ( name = `keydate` value = `2024-06-15` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = call-request_type exp = `ZZXXMLA1_A01 2024-06-15` ).
    cl_abap_unit_assert=>assert_equals( act = call-mdx exp = `<no XMLA` ).
  ENDMETHOD.

  METHOD with_sql.
    DATA(result) = NEW zzxxmla1_cl_bw_mdx_api( )->handle(
                     VALUE #( method     = `POST` path = `/bw/check` body = c_statement
                              parameters = VALUE #( ( name = `sql` value = `true` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = result-status exp = 200 ).
    " the members are read while the statement is resolved
    cl_abap_unit_assert=>assert_char_cp( act = result-body exp = `*"sql":[{"sql":*"phase":"Resolve"}*` ).
  ENDMETHOD.

ENDCLASS.
