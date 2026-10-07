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
"! Reads the FoodMart providers ZZXXMLA1_CL_BW_FOODMART_GEN creates (docs/environment.md, FoodMart data for the BW
"! cube): the InfoCube ZFMSALES and the cube-type aDSO ZFMSALESA. Only reads.
CLASS ltc_bw_provider DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    DATA cut TYPE REF TO zzxxmla1_cl_bw_provider.
    METHODS setup.
    METHODS providers FOR TESTING.
    METHODS adso FOR TESTING RAISING cx_static_check.
    METHODS cube FOR TESTING RAISING cx_static_check.
    METHODS demo_cube FOR TESTING RAISING cx_static_check.
    METHODS unknown_provider FOR TESTING.
ENDCLASS.

CLASS ltc_bw_provider IMPLEMENTATION.

  METHOD setup.
    cut = NEW #( ).
  ENDMETHOD.

  METHOD providers.
    DATA(providers) = cut->providers( ).
    cl_abap_unit_assert=>assert_equals( act = providers[ name = `ZFMSALES` ]-kind
                                        exp = zzxxmla1_cl_bw_provider=>c_kind-cube ).
    cl_abap_unit_assert=>assert_equals( act = providers[ name = `ZFMSALESA` ]-kind
                                        exp = zzxxmla1_cl_bw_provider=>c_kind-adso ).
    cl_abap_unit_assert=>assert_equals( act = providers[ name = `ZFMSALESA` ]-infoarea exp = `ZFOODMART` ).
  ENDMETHOD.

  METHOD adso.
    DATA(provider) = cut->read( 'zfmsalesa' ).
    cl_abap_unit_assert=>assert_equals( act = provider-name exp = `ZFMSALESA` ).
    cl_abap_unit_assert=>assert_equals( act = provider-kind exp = zzxxmla1_cl_bw_provider=>c_kind-adso ).
    cl_abap_unit_assert=>assert_equals( act = provider-text exp = `FoodMart Sales (aDSO)` ).
    cl_abap_unit_assert=>assert_equals( act = provider-fact_table exp = `/BIC/AZFMSALESA7` ).
    cl_abap_unit_assert=>assert_equals(
      act = VALUE string_table( FOR c IN provider-characteristics ( c-iobjnm ) )
      exp = VALUE string_table( ( `ZFMPROD` ) ( `ZFMCUST` ) ( `ZFMSTORE` ) ( `ZFMPROMO` ) ( `0CALDAY` ) ( `0CALWEEK` )
                                ( `0CALMONTH` ) ( `0CALQUARTER` ) ( `0CALYEAR` ) ) ).
    " an aDSO holds the value: the fact column is the characteristic's field
    DATA(store) = provider-characteristics[ iobjnm = `ZFMSTORE` ].
    cl_abap_unit_assert=>assert_equals( act = store-fact_column
                                        exp = VALUE zzxxmla1_cl_bw_provider=>ty_column( name     = `/BIC/ZFMSTORE`
                                                                                        datatype = `NUMC`
                                                                                        length   = 10 ) ).
    cl_abap_unit_assert=>assert_equals( act = store-has_sids exp = abap_true ).
    cl_abap_unit_assert=>assert_equals( act = store-basic exp = `ZFMSTORE` ).
    cl_abap_unit_assert=>assert_equals( act = store-view exp = `ZZXXMLA1V0000003` ).
    cl_abap_unit_assert=>assert_equals( act = store-key_column-name exp = `ZFMSTORE` ).
    cl_abap_unit_assert=>assert_initial( store-text_column ).
    cl_abap_unit_assert=>assert_equals( act = lines( store-attributes ) exp = 12 ).
    cl_abap_unit_assert=>assert_equals( act = store-attributes[ 1 ]
                                        exp = VALUE zzxxmla1_cl_bw_provider=>ty_attribute(
                                                iobjnm = `ZFMSNAME`
                                                text   = `Store Name`
                                                column = VALUE #( name = `ZFMSNAME` datatype = `CHAR` length = 60 ) ) ).
    DATA(day) = provider-characteristics[ iobjnm = `0CALDAY` ].
    cl_abap_unit_assert=>assert_equals( act = day-iobjtp exp = `TIM` ).
    cl_abap_unit_assert=>assert_equals( act = day-fact_column-name exp = `CALDAY` ).
    cl_abap_unit_assert=>assert_equals( act = day-fact_column-datatype exp = `DATS` ).

    cl_abap_unit_assert=>assert_equals(
      act = VALUE string_table( FOR k IN provider-key_figures ( |{ k-iobjnm } { k-fact_column-name } { k-aggregation }| ) )
      exp = VALUE string_table( ( `ZFMUNITS /BIC/ZFMUNITS SUM` ) ( `ZFMSCOST /BIC/ZFMSCOST SUM` )
                                ( `ZFMSSALES /BIC/ZFMSSALES SUM` ) ) ).
  ENDMETHOD.

  METHOD cube.
    DATA(provider) = cut->read( 'ZFMSALES' ).
    cl_abap_unit_assert=>assert_equals( act = provider-kind exp = zzxxmla1_cl_bw_provider=>c_kind-cube ).
    cl_abap_unit_assert=>assert_equals( act = provider-fact_table exp = `/BIC/FZFMSALES` ).
    " an InfoCube holds SIDs; the package dimension is left out
    cl_abap_unit_assert=>assert_equals(
      act = VALUE string_table( FOR c IN provider-characteristics ( c-fact_column-name ) )
      exp = VALUE string_table( ( `SID_ZFMPROD` ) ( `SID_ZFMCUST` ) ( `SID_ZFMSTORE` ) ( `SID_ZFMPROMO` )
                                ( `SID_ZFMDATE` ) ) ).
    DATA(date) = provider-characteristics[ iobjnm = `ZFMDATE` ].
    cl_abap_unit_assert=>assert_equals( act = date-view exp = `ZZXXMLA1V0000005` ).
    cl_abap_unit_assert=>assert_equals( act = lines( date-attributes ) exp = 9 ).
    cl_abap_unit_assert=>assert_equals( act = lines( provider-key_figures ) exp = 3 ).
    cl_abap_unit_assert=>assert_initial( provider-notes ).
  ENDMETHOD.

  METHOD demo_cube.
    " docs/bw-schema-design-guide.md, section 5: the cube switches on Country of the company code, none of the
    " ship-to party (a reference of the customer, whose Country and Industry are navigation attributes in BW)
    DATA(provider) = cut->read( '0D_NW_C01' ).
    DATA(code) = provider-characteristics[ iobjnm = `0D_NW_CODE` ].
    cl_abap_unit_assert=>assert_equals( act = code-text_column exp = `TXTMD` ).
    cl_abap_unit_assert=>assert_equals(
      act = VALUE string_table( FOR a IN code-attributes ( |{ a-iobjnm } { a-column-name } { a-text_column } { a-navigation }| ) )
      exp = VALUE string_table( ( `0D_NW_CNTRY D_NW_CNTRY D_NW_CNTRY_TXT X` ) ) ).
    DATA(ship) = provider-characteristics[ iobjnm = `0D_NW_SHIP` ].
    cl_abap_unit_assert=>assert_equals( act = ship-basic exp = `0D_NW_CUST` ).
    cl_abap_unit_assert=>assert_equals( act = ship-key_column-name exp = `D_NW_CUST` ).
    cl_abap_unit_assert=>assert_equals( act = VALUE string_table( FOR a IN ship-attributes ( |{ a-iobjnm } { a-navigation }| ) )
                                        exp = VALUE string_table( ( `0D_NW_CNTRY ` ) ( `0D_NW_IND ` ) ) ).
    " the time-dependent product group is an attribute like the others, read at the key date
    DATA(product) = provider-characteristics[ iobjnm = `0D_NW_PROD` ].
    cl_abap_unit_assert=>assert_equals( act = VALUE string_table( FOR a IN product-attributes ( |{ a-iobjnm } { a-navigation }| ) )
                                        exp = VALUE string_table( ( `0D_NW_PRDCT X` ) ( `0D_NW_PRDGP X` ) ) ).
    cl_abap_unit_assert=>assert_false( xsdbool( line_exists( provider-notes[ iobjnm = `0D_NW_PRDGP` ] ) ) ).
  ENDMETHOD.

  METHOD unknown_provider.
    TRY.
        cut->read( 'ZZXXMLA1_NONE' ).
        cl_abap_unit_assert=>fail( `no error` ).
      CATCH zzxxmla1_cx_bw_provider INTO DATA(error).
        cl_abap_unit_assert=>assert_char_cp( act = error->get_text( ) exp = 'ZZXXMLA1_NONE is neither*' ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
