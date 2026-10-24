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
"! What a traced call records of its request, and the gzip of its response; nothing is read or written.
CLASS ltc_trace DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    METHODS execute_statement FOR TESTING.
    METHODS discover_rowset FOR TESTING.
    METHODS no_xmla FOR TESTING.
    METHODS zipped_response FOR TESTING.
    METHODS faults FOR TESTING.
    METHODS two_hours FOR TESTING.
ENDCLASS.

CLASS zzxxmla1_cl_trace DEFINITION LOCAL FRIENDS ltc_trace.

CLASS ltc_trace IMPLEMENTATION.

  METHOD execute_statement.
    DATA(call) = zzxxmla1_cl_trace=>describe(
      `<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/"><SOAP-ENV:Body>` &&
      `<Execute xmlns="urn:schemas-microsoft-com:xml-analysis"><Command><Statement>` &&
      `SELECT {[Measures].[Unit Sales]} ON COLUMNS FROM [Sales] WHERE [Time].[1997] &amp; 1 &lt; 2` &&
      `</Statement></Command><Properties><PropertyList><Catalog>FoodMart</Catalog></PropertyList></Properties>` &&
      `</Execute></SOAP-ENV:Body></SOAP-ENV:Envelope>` ).
    cl_abap_unit_assert=>assert_equals( act = call-xmla_method exp = `EXECUTE` ).
    cl_abap_unit_assert=>assert_equals(
      act = call-mdx
      exp = `SELECT {[Measures].[Unit Sales]} ON COLUMNS FROM [Sales] WHERE [Time].[1997] & 1 < 2` ).
  ENDMETHOD.

  METHOD discover_rowset.
    DATA(call) = zzxxmla1_cl_trace=>describe(
      `<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/"><SOAP-ENV:Body>` &&
      `<Discover xmlns="urn:schemas-microsoft-com:xml-analysis"><RequestType>MDSCHEMA_CUBES</RequestType>` &&
      `<Restrictions><RestrictionList/></Restrictions><Properties><PropertyList/></Properties>` &&
      `</Discover></SOAP-ENV:Body></SOAP-ENV:Envelope>` ).
    cl_abap_unit_assert=>assert_equals( act = call-xmla_method exp = `DISCOVER` ).
    cl_abap_unit_assert=>assert_equals( act = call-request_type exp = `MDSCHEMA_CUBES` ).
    cl_abap_unit_assert=>assert_initial( call-mdx ).
  ENDMETHOD.

  METHOD no_xmla.
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_trace=>describe( `not xml` ) ).
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_trace=>describe( `` ) ).
  ENDMETHOD.

  METHOD zipped_response.
    DATA(text) = |<root>{ repeat( val = |<row a="1">Caf{ cl_abap_conv_in_ce=>uccp( '00E9' ) }</row>| occ = 1000 ) }</root>|.
    DATA(zipped) = zzxxmla1_cl_trace=>compress( text ).
    cl_abap_unit_assert=>assert_true( xsdbool( xstrlen( zipped ) > 0 AND xstrlen( zipped ) < strlen( text ) DIV 10 ) ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_trace=>decompress( zipped ) exp = text ).
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_trace=>compress( `` ) ).
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_trace=>decompress( VALUE xstring( ) ) ).
  ENDMETHOD.

  METHOD faults.
    cl_abap_unit_assert=>assert_true( zzxxmla1_cl_trace=>is_fault(
      `<SOAP-ENV:Envelope><SOAP-ENV:Body><SOAP-ENV:Fault><faultcode>x</faultcode></SOAP-ENV:Fault>` ) ).
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_trace=>is_fault(
      `<SOAP-ENV:Envelope><SOAP-ENV:Body><ExecuteResponse><return><root/></return></ExecuteResponse>` ) ).
  ENDMETHOD.

  METHOD two_hours.
    " over midnight and the end of a year: a trace is on for c_active_hours
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_trace=>c_active_hours exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_trace=>active_until( CONV #( '20261231233000.5000000' ) )
                                        exp = CONV timestampl( '20270101013000.5000000' ) ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_trace=>seconds_before( tstmp   = CONV #( '20270101013000' )
                                                                                 seconds = 7 * 86400 )
                                        exp = CONV timestampl( '20261225013000' ) ).
  ENDMETHOD.

ENDCLASS.
