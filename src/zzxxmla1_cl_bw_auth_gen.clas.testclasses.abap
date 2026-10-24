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
CLASS ltc_bw_auth_gen DEFINITION DEFERRED.
CLASS zzxxmla1_cl_bw_auth_gen DEFINITION LOCAL FRIENDS ltc_bw_auth_gen.

CLASS ltc_bw_auth_gen DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    "! every scenario has its own test user, and every authorization it names exists
    METHODS scenarios_consistent FOR TESTING.
    "! every authorization is named ZCLA_*, used by a scenario and restricts a characteristic
    METHODS authorizations_used FOR TESTING.
    "! only ZZXXMLA1_A and two digits are test users: run and delete never touch another user
    METHODS test_users FOR TESTING.
ENDCLASS.


CLASS ltc_bw_auth_gen IMPLEMENTATION.

  METHOD scenarios_consistent.
    DATA(scenarios) = zzxxmla1_cl_bw_auth_gen=>scenarios( ).
    DATA(authorizations) = zzxxmla1_cl_bw_auth_gen=>authorizations( ).
    LOOP AT scenarios INTO DATA(scenario).
      cl_abap_unit_assert=>assert_true( act = zzxxmla1_cl_bw_auth_gen=>is_test_user( scenario-user )
                                        msg = |{ scenario-user }| ).
      DATA(count) = REDUCE i( INIT n = 0 FOR s IN scenarios WHERE ( user = scenario-user ) NEXT n = n + 1 ).
      cl_abap_unit_assert=>assert_equals( act = count exp = 1 msg = |{ scenario-user } twice| ).
      LOOP AT scenario-auths INTO DATA(auth).
        cl_abap_unit_assert=>assert_true( act = xsdbool( line_exists( authorizations[ name = auth ] ) )
                                          msg = |{ scenario-name }: { auth } missing| ).
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD authorizations_used.
    DATA(scenarios) = zzxxmla1_cl_bw_auth_gen=>scenarios( ).
    LOOP AT zzxxmla1_cl_bw_auth_gen=>authorizations( ) INTO DATA(authorization).
      cl_abap_unit_assert=>assert_true(
        act = xsdbool( authorization-name CP |{ zzxxmla1_cl_bw_auth_gen=>c_auth_prefix }*| )
        msg = |{ authorization-name }| ).
      DATA(used) = abap_false.
      LOOP AT scenarios INTO DATA(scenario).
        IF line_exists( scenario-auths[ table_line = authorization-name ] ).
          used = abap_true.
        ENDIF.
      ENDLOOP.
      cl_abap_unit_assert=>assert_true( act = used msg = |{ authorization-name } unused| ).
      cl_abap_unit_assert=>assert_true(
        act = xsdbool( authorization-ranges IS NOT INITIAL OR authorization-hierarchies IS NOT INITIAL )
        msg = |{ authorization-name } empty| ).
      cl_abap_unit_assert=>assert_not_initial( act = authorization-text msg = |{ authorization-name } text| ).
    ENDLOOP.
  ENDMETHOD.

  METHOD test_users.
    cl_abap_unit_assert=>assert_true( zzxxmla1_cl_bw_auth_gen=>is_test_user( `ZZXXMLA1_A07` ) ).
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_bw_auth_gen=>is_test_user( `ZZXXMLA1_ADMIN` ) ).
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_bw_auth_gen=>is_test_user( `ZZXXMLA1_A1` ) ).
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_bw_auth_gen=>is_test_user( `DEVELOPER` ) ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_bw_auth_gen=>user( 3 ) exp = `ZZXXMLA1_A03` ).
  ENDMETHOD.

ENDCLASS.
