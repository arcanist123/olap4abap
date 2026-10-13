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
CLASS ltc_bw_selection DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    TYPES ty_t_row TYPE zzxxmla1_cl_bw_selection=>ty_t_row.

    "! the special periods excluded, as the user may write them: lower case, blanks, unsorted, a duplicate
    METHODS parse_canonical FOR TESTING RAISING cx_static_check.
    "! BT and NB with their high value, a separator inside a value
    METHODS parse_high_values FOR TESTING RAISING cx_static_check.
    "! texts that are no range table
    METHODS parse_refused FOR TESTING.
    "! rows the class cannot write
    METHODS check_refused FOR TESTING.
    "! a single I EQ value is written short, as fixing wrote it; ranges with their rows; characteristics sorted
    METHODS selection_text FOR TESTING.
    "! every option, included and excluded (negated), patterns as LIKE
    METHODS condition FOR TESTING.
    "! I rows with OR, E rows each with AND
    METHODS condition_combined FOR TESTING.
    "! filter, members and the fixed value fixing wrote; other annotations are none
    METHODS annotations FOR TESTING RAISING cx_static_check.
    "! a single I EQ value only
    METHODS single FOR TESTING.

    "! whether check refuses the rows
    METHODS refused
      IMPORTING !rows         TYPE ty_t_row
      RETURNING VALUE(result) TYPE abap_bool.
    "! whether parse refuses the text
    METHODS parse_fails
      IMPORTING text          TYPE string
      RETURNING VALUE(result) TYPE abap_bool.
ENDCLASS.


CLASS ltc_bw_selection IMPLEMENTATION.

  METHOD parse_canonical.
    DATA(rows) = zzxxmla1_cl_bw_selection=>parse( ` e cp '*016'; E CP '*013';E CP '*016' ;  e Cp '*014'` ).
    cl_abap_unit_assert=>assert_equals(
        act = rows
        exp = VALUE ty_t_row( ( sign = 'E' option = 'CP' low = `*013` )
                              ( sign = 'E' option = 'CP' low = `*014` )
                              ( sign = 'E' option = 'CP' low = `*016` ) ) ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_bw_selection=>rows_text( rows )
                                        exp = `E CP '*013';E CP '*014';E CP '*016'` ).
  ENDMETHOD.

  METHOD parse_high_values.
    DATA(rows) = zzxxmla1_cl_bw_selection=>parse( `I BT '2024001' '2024012';E NB 'A;B' 'Z' ;I EQ ''` ).
    cl_abap_unit_assert=>assert_equals(
        act = rows
        exp = VALUE ty_t_row( ( sign = 'E' option = 'NB' low = `A;B` high = `Z` )
                              ( sign = 'I' option = 'BT' low = `2024001` high = `2024012` )
                              ( sign = 'I' option = 'EQ' low = `` ) ) ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_bw_selection=>rows_text( rows )
                                        exp = `E NB 'A;B' 'Z';I BT '2024001' '2024012';I EQ ''` ).
  ENDMETHOD.

  METHOD parse_refused.
    cl_abap_unit_assert=>assert_true( parse_fails( `` ) ).
    cl_abap_unit_assert=>assert_true( parse_fails( `I EQ 'K4` ) ).
    cl_abap_unit_assert=>assert_true( parse_fails( `I EQ K4` ) ).
    cl_abap_unit_assert=>assert_true( parse_fails( `I EQ 'K4' X` ) ).
    cl_abap_unit_assert=>assert_true( parse_fails( `I EQ 'K4';` ) ).
    cl_abap_unit_assert=>assert_true( parse_fails( `X EQ 'K4'` ) ).
    cl_abap_unit_assert=>assert_true( parse_fails( `I XX 'K4'` ) ).
    cl_abap_unit_assert=>assert_true( parse_fails( `I EQ 'K4' 'K5'` ) ).
    cl_abap_unit_assert=>assert_false( parse_fails( `I EQ 'K4'` ) ).
  ENDMETHOD.

  METHOD check_refused.
    cl_abap_unit_assert=>assert_true( refused( VALUE #( ) ) ).
    cl_abap_unit_assert=>assert_true( refused( VALUE #( ( sign = 'I' option = 'EQ' low = `K'4` ) ) ) ).
    cl_abap_unit_assert=>assert_true( refused( VALUE #( ( sign = 'I' option = 'BT' low = `2` ) ) ) ).
    cl_abap_unit_assert=>assert_true( refused( VALUE #( ( sign = 'I' option = 'BT' low = `2` high = `1` ) ) ) ).
    cl_abap_unit_assert=>assert_true( refused( VALUE #( ( sign = 'I' option = 'GT' low = `2` high = `3` ) ) ) ).
    cl_abap_unit_assert=>assert_true( refused( VALUE #( ( sign = 'I' option = 'CP' low = `A_*` ) ) ) ).
    cl_abap_unit_assert=>assert_true( refused( VALUE #( ( sign = 'E' option = 'NP' low = `100%` ) ) ) ).
    cl_abap_unit_assert=>assert_false( refused( VALUE #( ( sign = 'I' option = 'BT' low = `1` high = `1` ) ) ) ).
    cl_abap_unit_assert=>assert_false( refused( VALUE #( ( sign = 'E' option = 'CP' low = `*01+` ) ) ) ).
  ENDMETHOD.

  METHOD selection_text.
    DATA(selection) = VALUE zzxxmla1_cl_bw_selection=>ty_t_characteristic(
        ( iobjnm = '0FISCVARNT' mode = zzxxmla1_cl_bw_selection=>c_mode-filter
          rows   = zzxxmla1_cl_bw_selection=>equals( `K4` ) )
        ( iobjnm = '0FISCPER' mode = zzxxmla1_cl_bw_selection=>c_mode-members
          rows   = VALUE #( ( sign = 'E' option = 'CP' low = `*014` )
                            ( sign = 'E' option = 'CP' low = `*013` )
                            ( sign = 'E' option = 'CP' low = `*013` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_bw_selection=>selection_text( selection )
                                        exp = `0FISCPER=E CP '*013',E CP '*014';0FISCVARNT=K4` ).
    " the mode is not part of it
    selection[ iobjnm = '0FISCPER' ]-mode = zzxxmla1_cl_bw_selection=>c_mode-filter.
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_bw_selection=>selection_text( selection )
                                        exp = `0FISCPER=E CP '*013',E CP '*014';0FISCVARNT=K4` ).
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_bw_selection=>selection_text( VALUE #( ) ) ).
  ENDMETHOD.

  METHOD condition.
    DATA(options) = VALUE string_table( ( `EQ` ) ( `NE` ) ( `GT` ) ( `GE` ) ( `LT` ) ( `LE` ) ( `CP` ) ( `NP` ) ).
    DATA(included) = VALUE string_table( ( `c = '5'` ) ( `c <> '5'` ) ( `c > '5'` ) ( `c >= '5'` ) ( `c < '5'` )
                                         ( `c <= '5'` ) ( `c like '5'` ) ( `c not like '5'` ) ).
    DATA(excluded) = VALUE string_table( ( `c <> '5'` ) ( `c = '5'` ) ( `c <= '5'` ) ( `c < '5'` ) ( `c >= '5'` )
                                         ( `c > '5'` ) ( `c not like '5'` ) ( `c like '5'` ) ).
    LOOP AT options INTO DATA(option).
      DATA(index) = sy-tabix.
      cl_abap_unit_assert=>assert_equals(
          act = zzxxmla1_cl_bw_selection=>condition( rows   = VALUE #( ( sign = 'I' option = option low = `5` ) )
                                                     column = `c` )
          exp = included[ index ]
          msg = |I { option }| ).
      cl_abap_unit_assert=>assert_equals(
          act = zzxxmla1_cl_bw_selection=>condition( rows   = VALUE #( ( sign = 'E' option = option low = `5` ) )
                                                     column = `c` )
          exp = excluded[ index ]
          msg = |E { option }| ).
    ENDLOOP.
    cl_abap_unit_assert=>assert_equals(
        act = zzxxmla1_cl_bw_selection=>condition( rows   = VALUE #( ( sign = 'I' option = 'BT' low = `1` high = `2` ) )
                                                   column = `c` )
        exp = `c between '1' and '2'` ).
    cl_abap_unit_assert=>assert_equals(
        act = zzxxmla1_cl_bw_selection=>condition( rows   = VALUE #( ( sign = 'E' option = 'BT' low = `1` high = `2` ) )
                                                   column = `c` )
        exp = `c not between '1' and '2'` ).
    cl_abap_unit_assert=>assert_equals(
        act = zzxxmla1_cl_bw_selection=>condition( rows   = VALUE #( ( sign = 'I' option = 'NB' low = `1` high = `2` ) )
                                                   column = `c` )
        exp = `c not between '1' and '2'` ).
    cl_abap_unit_assert=>assert_equals(
        act = zzxxmla1_cl_bw_selection=>condition( rows   = VALUE #( ( sign = 'I' option = 'CP' low = `*01+` ) )
                                                   column = `s.FISCPER` )
        exp = `s.FISCPER like '%01_'` ).
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_bw_selection=>condition( rows = VALUE #( ) column = `c` ) ).
  ENDMETHOD.

  METHOD condition_combined.
    cl_abap_unit_assert=>assert_equals(
        act = zzxxmla1_cl_bw_selection=>condition(
                  rows   = VALUE #( ( sign = 'E' option = 'CP' low = `*013` )
                                    ( sign = 'I' option = 'BT' low = `2024001` high = `2025016` )
                                    ( sign = 'I' option = 'EQ' low = `2023012` )
                                    ( sign = 'E' option = 'CP' low = `*014` ) )
                  column = `"FISCPER"` )
        exp = `( "FISCPER" between '2024001' and '2025016' or "FISCPER" = '2023012' ) and ` &&
              `"FISCPER" not like '%013' and "FISCPER" not like '%014'` ).
    cl_abap_unit_assert=>assert_equals(
        act = zzxxmla1_cl_bw_selection=>condition( rows   = zzxxmla1_cl_bw_selection=>equals( `K4` )
                                                   column = `s.FISCVARNT` )
        exp = `s.FISCVARNT = 'K4'` ).
  ENDMETHOD.

  METHOD annotations.
    DATA(filter) = zzxxmla1_cl_bw_selection=>from_annotation( name = `olap4abap.filter.0VERSION`
                                                             value = `I BT '000' '001'` ).
    cl_abap_unit_assert=>assert_equals( act = filter-iobjnm exp = '0VERSION' ).
    cl_abap_unit_assert=>assert_equals( act = filter-mode exp = zzxxmla1_cl_bw_selection=>c_mode-filter ).
    cl_abap_unit_assert=>assert_equals( act = filter-rows
                                        exp = VALUE ty_t_row( ( sign = 'I' option = 'BT' low = `000` high = `001` ) ) ).
    DATA(members) = zzxxmla1_cl_bw_selection=>from_annotation( name = `olap4abap.members.0FISCPER`
                                                              value = `E CP '*013'` ).
    cl_abap_unit_assert=>assert_equals( act = members-mode exp = zzxxmla1_cl_bw_selection=>c_mode-members ).
    cl_abap_unit_assert=>assert_equals(
        act = zzxxmla1_cl_bw_selection=>annotation_name( characteristic = members-iobjnm mode = members-mode )
        exp = `olap4abap.members.0FISCPER` ).
    DATA(fixed) = zzxxmla1_cl_bw_selection=>from_annotation( name = `olap4abap.fixed.0FISCVARNT` value = `K4` ).
    cl_abap_unit_assert=>assert_equals( act = fixed-iobjnm exp = '0FISCVARNT' ).
    cl_abap_unit_assert=>assert_equals( act = fixed-mode exp = zzxxmla1_cl_bw_selection=>c_mode-filter ).
    cl_abap_unit_assert=>assert_equals( act = fixed-rows exp = zzxxmla1_cl_bw_selection=>equals( `K4` ) ).
    cl_abap_unit_assert=>assert_equals(
        act = zzxxmla1_cl_bw_selection=>annotation_name( characteristic = fixed-iobjnm mode = fixed-mode )
        exp = `olap4abap.filter.0FISCVARNT` ).
    cl_abap_unit_assert=>assert_initial(
        zzxxmla1_cl_bw_selection=>from_annotation( name = `olap4abap.membersWithFacts` value = `true` ) ).
    cl_abap_unit_assert=>assert_initial(
        zzxxmla1_cl_bw_selection=>from_annotation( name = `olap4abap.filter.` value = `I EQ 'x'` ) ).
    TRY.
        zzxxmla1_cl_bw_selection=>from_annotation( name = `olap4abap.members.0FISCPER` value = `E CP *013` ).
        cl_abap_unit_assert=>fail( `a value without quotes` ).
      CATCH zzxxmla1_cx_bw_provider INTO DATA(error).
        cl_abap_unit_assert=>assert_char_cp( act = error->error_message
                                             exp = `Annotation olap4abap.members.0FISCPER:*` ).
    ENDTRY.
  ENDMETHOD.

  METHOD single.
    cl_abap_unit_assert=>assert_true( zzxxmla1_cl_bw_selection=>is_single( zzxxmla1_cl_bw_selection=>equals( `K4` ) ) ).
    cl_abap_unit_assert=>assert_equals(
        act = zzxxmla1_cl_bw_selection=>single_value( zzxxmla1_cl_bw_selection=>equals( `K4` ) )
        exp = `K4` ).
    cl_abap_unit_assert=>assert_false(
        zzxxmla1_cl_bw_selection=>is_single( VALUE #( ( sign = 'E' option = 'EQ' low = `K4` ) ) ) ).
    cl_abap_unit_assert=>assert_false(
        zzxxmla1_cl_bw_selection=>is_single( VALUE #( ( sign = 'I' option = 'CP' low = `K4` ) ) ) ).
    cl_abap_unit_assert=>assert_false(
        zzxxmla1_cl_bw_selection=>is_single( VALUE #( ( sign = 'I' option = 'EQ' low = `K1` )
                                                      ( sign = 'I' option = 'EQ' low = `K4` ) ) ) ).
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_bw_selection=>is_single( VALUE #( ) ) ).
    cl_abap_unit_assert=>assert_initial(
        zzxxmla1_cl_bw_selection=>single_value( VALUE #( ( sign = 'I' option = 'NE' low = `K4` ) ) ) ).
  ENDMETHOD.

  METHOD refused.
    TRY.
        zzxxmla1_cl_bw_selection=>check( characteristic = `C` rows = rows ).
      CATCH zzxxmla1_cx_bw_provider.
        result = abap_true.
    ENDTRY.
  ENDMETHOD.

  METHOD parse_fails.
    TRY.
        zzxxmla1_cl_bw_selection=>parse( text ).
      CATCH zzxxmla1_cx_bw_provider.
        result = abap_true.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
