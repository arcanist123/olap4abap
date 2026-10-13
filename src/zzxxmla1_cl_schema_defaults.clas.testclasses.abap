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
CLASS ltc_defaults DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    "! the variant fixed to K4, the period restricted to its regular periods, year and period time
    METHODS fiscal_provider FOR TESTING.
    "! only the year: K4 fixed, the year time, nothing restricted on members
    METHODS fiscal_year_only FOR TESTING.
    "! no defaults without the variant, or for a fiscal period not compounded with it (the clinic demo's own)
    METHODS no_fiscal_time FOR TESTING.
    "! I CP '*001' to I CP '*012'
    METHODS regular_period_rows FOR TESTING RAISING zzxxmla1_cx_bw_provider.
    "! a provider of characteristics: the variant and the fiscal ones compounded with it
    METHODS provider
      IMPORTING iobjnms       TYPE string_table
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_provider=>ty_provider.
ENDCLASS.

CLASS ltc_defaults IMPLEMENTATION.

  METHOD provider.
    result-name = `ZTEST`.
    LOOP AT iobjnms INTO DATA(iobjnm).
      APPEND VALUE #( iobjnm      = iobjnm
                      has_sids    = abap_true
                      compounding = COND #( WHEN iobjnm CP '0FISC*' AND iobjnm <> `0FISCVARNT`
                                            THEN VALUE #( ( `0FISCVARNT` ) ) ) ) TO result-characteristics.
    ENDLOOP.
  ENDMETHOD.

  METHOD fiscal_provider.
    DATA(defaults) = zzxxmla1_cl_schema_defaults=>fiscal_defaults(
      provider( VALUE #( ( `0FISCVARNT` ) ( `0FISCYEAR` ) ( `0FISCPER` ) ( `0MATERIAL` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( defaults-selection ) exp = 2 ).
    DATA(variant) = defaults-selection[ iobjnm = '0FISCVARNT' ].
    cl_abap_unit_assert=>assert_equals( act = variant-mode exp = zzxxmla1_cl_bw_selection=>c_mode-filter ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_bw_selection=>single_value( variant-rows ) exp = `K4` ).
    DATA(period) = defaults-selection[ iobjnm = '0FISCPER' ].
    cl_abap_unit_assert=>assert_equals( act = period-mode exp = zzxxmla1_cl_bw_selection=>c_mode-members ).
    cl_abap_unit_assert=>assert_equals( act = period-rows exp = zzxxmla1_cl_schema_defaults=>regular_periods( ) ).
    cl_abap_unit_assert=>assert_equals( act = defaults-time exp = VALUE string_table( ( `0FISCYEAR` ) ( `0FISCPER` ) ) ).
  ENDMETHOD.

  METHOD fiscal_year_only.
    DATA(defaults) = zzxxmla1_cl_schema_defaults=>fiscal_defaults(
      provider( VALUE #( ( `0FISCVARNT` ) ( `0FISCYEAR` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( defaults-selection ) exp = 1 ).
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists( defaults-selection[ iobjnm = '0FISCVARNT' ] ) ) ).
    cl_abap_unit_assert=>assert_equals( act = defaults-time exp = VALUE string_table( ( `0FISCYEAR` ) ) ).
  ENDMETHOD.

  METHOD no_fiscal_time.
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_schema_defaults=>fiscal_defaults(
      provider( VALUE #( ( `0FISCYEAR` ) ( `0FISCPER` ) ) ) ) ).
    DATA(provider) = provider( VALUE #( ( `0FISCVARNT` ) ( `ZCLFISCPR` ) ) ).
    provider-characteristics[ iobjnm = `ZCLFISCPR` ]-compounding = VALUE #( ( `0FISCVARNT` ) ).
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_schema_defaults=>fiscal_defaults( provider ) ).
  ENDMETHOD.

  METHOD regular_period_rows.
    DATA(rows) = zzxxmla1_cl_schema_defaults=>regular_periods( ).
    cl_abap_unit_assert=>assert_equals( act = lines( rows ) exp = 12 ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 1 ] exp = VALUE zzxxmla1_cl_bw_selection=>ty_row(
                                          sign = 'I' option = 'CP' low = `*001` ) ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 12 ]-low exp = `*012` ).
    " a range table the selection class accepts
    zzxxmla1_cl_bw_selection=>check( characteristic = `0FISCPER` rows = rows ).
  ENDMETHOD.

ENDCLASS.
