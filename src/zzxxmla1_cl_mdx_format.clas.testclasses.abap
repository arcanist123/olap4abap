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
CLASS ltc_format DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    METHODS default_pattern FOR TESTING.
    METHODS rounds_half_even FOR TESTING.
    METHODS negative_and_zero FOR TESTING.
    METHODS fixed_decimals FOR TESTING.
    METHODS standard_format FOR TESTING.
    METHODS java_double FOR TESTING.
    METHODS xmla_double FOR TESTING.
    METHODS assert_java
      IMPORTING value TYPE f
                exp   TYPE string.
    "! Format.format of the number given as text (as FormatTest gives it).
    METHODS assert_number
      IMPORTING value  TYPE string
                format TYPE string
                exp    TYPE string.
    METHODS assert_text
      IMPORTING value  TYPE string
                format TYPE string
                exp    TYPE string.
    "! the single-line number cases of FormatTest (testTrickyNumbers, testNil, testSmallNegativeNumbers, ...)
    METHODS format_test_numbers FOR TESTING.
    "! formats with styles (testPercentWithStyle, testNegativePercentWithStyle) and the formats of the reference server's answers
    METHODS styles FOR TESTING.
    "! testString and predefined formats (checkNumbersInLocale)
    METHODS strings_and_macros FOR TESTING.
    "! The formats of CurrentDateMember (UdfTest) and Calendar's week of the year (en_US).
    METHODS dates FOR TESTING.
ENDCLASS.

CLASS ltc_format IMPLEMENTATION.
  METHOD default_pattern.
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_mdx_format=>format( value = 266773 ) exp = `266,773` ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_mdx_format=>format( value = CONV decfloat34( '565238.13' ) ) exp = `565,238.13` ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_mdx_format=>format( value = 86837 ) exp = `86,837` ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_mdx_format=>format( value = 1234567 ) exp = `1,234,567` ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_mdx_format=>format( value = 123 ) exp = `123` ).
    " a value below 1 keeps its integer digit (Store Sales 0.67 in NonEmptyTest)
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_mdx_format=>format( value = CONV decfloat34( '0.67' ) ) exp = `0.67` ).
  ENDMETHOD.

  METHOD rounds_half_even.
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_mdx_format=>format( value = CONV decfloat34( '225627.2336' ) ) exp = `225,627.234` ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_mdx_format=>format( value = CONV decfloat34( '0.125' ) pattern = `0.00` ) exp = `0.12` ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_mdx_format=>format( value = CONV decfloat34( '0.135' ) pattern = `0.00` ) exp = `0.14` ).
  ENDMETHOD.

  METHOD negative_and_zero.
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_mdx_format=>format( value = -1500 ) exp = `-1,500` ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_mdx_format=>format( value = 0 ) exp = `0` ).
  ENDMETHOD.

  METHOD fixed_decimals.
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_mdx_format=>format( value = 5 pattern = `#,##0.00` ) exp = `5.00` ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_mdx_format=>format( value = 12345 pattern = `#,##0.00` ) exp = `12,345.00` ).
  ENDMETHOD.

  METHOD standard_format.
    " Format.java: Standard is #,##0
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_mdx_format=>format( value = CONV decfloat34( '0.3333' )
                                                                              pattern = `Standard` ) exp = `0` ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_mdx_format=>format( value = 533546 pattern = `Standard` )
                                        exp = `533,546` ).
  ENDMETHOD.

  METHOD assert_java.
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_mdx_format=>java_double( value ) exp = exp ).
  ENDMETHOD.

  METHOD assert_number.
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_mdx_format=>format_number( value = CONV f( value ) format_string = format )
      exp = exp msg = |{ value } { format }| ).
  ENDMETHOD.

  METHOD assert_text.
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_mdx_format=>format_text( value = value format_string = format )
      exp = exp msg = |{ value } { format }| ).
  ENDMETHOD.

  METHOD format_test_numbers.
    assert_number( value = `40.385` format = `##0.0#` exp = `40.39` ).
    assert_number( value = `40.386` format = `##0.0#` exp = `40.39` ).
    assert_number( value = `40.384` format = `##0.0#` exp = `40.38` ).
    assert_number( value = `40.385` format = `##0.#` exp = `40.4` ).
    assert_number( value = `40.38` format = `##0.0#` exp = `40.38` ).
    assert_number( value = `-40.38` format = `##0.0#` exp = `-40.38` ).
    assert_number( value = `0.040385` format = `#0.###` exp = `0.04` ).
    assert_number( value = `0.040385` format = `#0.000` exp = `0.040` ).
    assert_number( value = `0.040385` format = `#0.####` exp = `0.0404` ).
    assert_number( value = `0.040385` format = `00.####` exp = `00.0404` ).
    assert_number( value = `0.040385` format = `.00#` exp = `.04` ).
    assert_number( value = `0.040785` format = `.00#` exp = `.041` ).
    assert_number( value = `99.9999` format = `##.####` exp = `99.9999` ).
    assert_number( value = `99.9999` format = `##` exp = `100` ).
    assert_number( value = `99.9999` format = `##.#` exp = `100.` ).
    assert_number( value = `99.9999` format = `##.###` exp = `100.` ).
    assert_number( value = `99.9999` format = `##.00#` exp = `100.00` ).
    assert_number( value = `.00099` format = `#.00` exp = `.00` ).
    assert_number( value = `.00099` format = `#.00#` exp = `.001` ).
    assert_number( value = `12.34` format = `#.000##` exp = `12.340` ).
    assert_number( value = `23` format = `#.#` exp = `23.` ).
    assert_number( value = `0` format = `#.#` exp = `.` ).
    assert_number( value = `1.9999999999999995E-6` format = `#.#######` exp = `.000002` ).
    assert_number( value = `4.699999999999999E-6` format = `#.#######` exp = `.0000047` ).
    assert_number( value = `-0.006` format = `#.0` exp = `.0` ).
    assert_number( value = `-0.006` format = `#.00` exp = `-.01` ).
    assert_number( value = `-0.0500001` format = `#.0` exp = `-.1` ).
    assert_number( value = `-0.0499999` format = `#.0` exp = `.0` ).
    assert_number( value = `-0.00006` format = `#.0%` exp = `.0%` ).
    assert_number( value = `-0.0006` format = `#.0%` exp = `-.1%` ).
    assert_number( value = `-0.0004` format = `#.0%` exp = `.0%` ).
    assert_number( value = `-0.0005` format = `#.0%` exp = `-.1%` ).
    assert_number( value = `-0.0005000001` format = `#.0%` exp = `-.1%` ).
    assert_number( value = `-0.00006` format = `#.00%` exp = `-.01%` ).
    assert_number( value = `-0.00004` format = `#.00%` exp = `.00%` ).
    assert_number( value = `-0.00006` format = `00000.00%` exp = `-00000.01%` ).
    assert_number( value = `-0.00004` format = `00000.00%` exp = `00000.00%` ).
    assert_number( value = `-0.001` format = `0.##;(0.##);Nil` exp = `Nil` ).
    assert_number( value = `-0.01` format = `0.##;(0.##);Nil` exp = `(0.01)` ).
    assert_number( value = `-0.01` format = `0.##;(0.#);Nil` exp = `Nil` ).
    assert_number( value = `0.00001` format = `#.##;(#.##)` exp = `.` ).
    assert_number( value = `0.001` format = `0.##;(0.##)` exp = `0.` ).
    assert_number( value = `-0.001` format = `0.##;(0.##)` exp = `0.` ).
    assert_number( value = `-0.0` format = `#0.000` exp = `0.000` ).
    assert_number( value = `-0.0` format = `#0` exp = `0` ).
    assert_number( value = `-0.0` format = `#0.0` exp = `0.0` ).
    assert_number( value = `-0.0364` format = `#.00%` exp = `-3.64%` ).
    assert_number( value = `0.0364` format = `#.00%` exp = `3.64%` ).
    assert_number( value = `0.50` format = `0` exp = `1` ).
    assert_number( value = `-1.5` format = `0` exp = `-2` ).
    assert_number( value = `-0.50` format = `0` exp = `-1` ).
    assert_number( value = `-0.99999999` format = `0.0` exp = `-1.0` ).
    assert_number( value = `-0.45` format = `#.0` exp = `-.5` ).
    assert_number( value = `-0.45` format = `0` exp = `0` ).
    assert_number( value = `-0.49999` format = `0` exp = `0` ).
    assert_number( value = `-0.49999` format = `0.0` exp = `-0.5` ).
    assert_number( value = `0.49999` format = `0` exp = `0` ).
    assert_number( value = `0.49999` format = `#.0` exp = `.5` ).
  ENDMETHOD.

  METHOD styles.
    assert_number( value = `0.0364` format = `|#.00%|style='green'` exp = `|3.64%|style='green'` ).
    " upstream bug 687 is not fixed: the minus comes after the leading |
    assert_number( value = `-0.0364` format = `|#.00%|style='red'` exp = `|-3.64%|style='red'` ).
    assert_number( value = `-364` format = `|#.00|style=red` exp = `|-364.00|style=red` ).
    assert_number( value = `364` format = `|#.00|style='green';|-#.000|style='red'` exp = `|364.00|style='green'` ).
    assert_number( value = `-364` format = `|#.00|style='green';|-#.000|style='red'` exp = `|-364.000|style='red'` ).
    " The reference server's answers
    assert_number( value = `533546` format = `|#,##0|style=red` exp = `|533,546|style=red` ).
    assert_number( value = `23` format = `|<|arrow="up"` exp = `|23|arrow=up` ).
    assert_number( value = `76.849` format = `|$#,##0.00|style=green` exp = `|$76.85|style=green` ).
    assert_number( value = `138.51` format = `|($#,##0.00)|style=red` exp = `|($138.51)|style=red` ).
  ENDMETHOD.

  METHOD strings_and_macros.
    assert_text( value = `Foo Bar` format = `|<|arrow="up"` exp = `|foo bar|arrow=up` ).
    assert_text( value = `This Is A Test` format = `>` exp = `THIS IS A TEST` ).
    assert_text( value = `This Is A Test` format = `<` exp = `this is a test` ).
    assert_text( value = `Foo Bar` format = `<@` exp = `foo bar@` ).
    assert_text( value = `Foo Bar` format = `<>` exp = `foo barFOO BAR` ).
    assert_text( value = `Foo Bar` format = `@` exp = `Foo Bar` ).
    assert_text( value = `Foo Bar` format = `E` exp = `Foo Bar` ).
    assert_text( value = `1 + 2` format = `Standard` exp = `1 + 2` ).
    assert_number( value = `123.45` format = `>` exp = `123.45` ).
    assert_number( value = `123.45` format = `@` exp = `@` ).
    assert_number( value = `123.45` format = `E` exp = `E` ).
    " checkNumbersInLocale: 6, -6, 0 and .6
    assert_number( value = `6` format = `Currency` exp = `$6.00` ).
    assert_number( value = `-6` format = `Currency` exp = `($6.00)` ).
    assert_number( value = `0` format = `Currency` exp = `$0.00` ).
    assert_number( value = `.6` format = `Currency` exp = `$0.60` ).
    assert_number( value = `.6` format = `Fixed` exp = `1` ).
    assert_number( value = `-6` format = `Standard` exp = `-6` ).
    assert_number( value = `.6` format = `Standard` exp = `1` ).
    assert_number( value = `6` format = `Percent` exp = `600.00%` ).
    assert_number( value = `-6` format = `Percent` exp = `-600.00%` ).
    assert_number( value = `0` format = `Percent` exp = `0.00%` ).
    assert_number( value = `-6` format = `Yes/No` exp = `Yes` ).
    assert_number( value = `0` format = `True/False` exp = `False` ).
    assert_number( value = `.6` format = `On/Off` exp = `On` ).
  ENDMETHOD.

  METHOD java_double.
    DATA value TYPE f.
    assert_java( value = 0 exp = `0.0` ).
    assert_java( value = 266773 exp = `266773.0` ).
    assert_java( value = CONV f( '225627.2336' ) exp = `225627.2336` ).
    assert_java( value = -2 / 8 exp = `-0.25` ).
    assert_java( value = CONV f( '0.001' ) exp = `0.001` ).
    assert_java( value = CONV f( '0.0001' ) exp = `1.0E-4` ).
    assert_java( value = 9999999 exp = `9999999.0` ).
    assert_java( value = 10000000 exp = `1.0E7` ).
    " the values of the reference server's answer to ([Store Sales] - [Store Cost]) / [Store Cost], 1 / 3, [Store Sales] * 10^9
    value = ( CONV f( '565238.13' ) - CONV f( '225627.2336' ) ) / CONV f( '225627.2336' ).
    assert_java( value = value exp = `1.505185748109088` ).
    value = CONV f( 1 ) / CONV f( 3 ).
    assert_java( value = value exp = `0.3333333333333333` ).
    value = CONV f( '565238.13' ) * CONV f( 1000000000 ).
    assert_java( value = value exp = `5.6523813E14` ).
    value = CONV f( '0.1' ) + CONV f( '0.2' ).
    assert_java( value = value exp = `0.30000000000000004` ).
    " 90.87539999999998 and ...99 are the same double; Java writes the one nearer to its exact value
    " (90.875399999999984856...), as the reference server does for Store Sales - Store Cost of product 90
    value = CONV f( '153.23' ) - CONV f( '62.3546' ).
    assert_java( value = value exp = `90.87539999999998` ).
  ENDMETHOD.

  METHOD xmla_double.
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_mdx_format=>xmla_double( 266773 ) exp = `266773` ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_mdx_format=>xmla_double( 10 ) exp = `10` ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_mdx_format=>xmla_double( 10000000 ) exp = `1.0E7` ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_mdx_format=>xmla_double( CONV f( '565238.13' ) )
                                        exp = `565238.13` ).
  ENDMETHOD.
  METHOD dates.
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_mdx_format=>format_date( date = '20261004' time = '133005'
                                                format_string = `[Ti\me]\.[yyyy]\.[Qq]\.[m]` )
      exp = `[Time].[2026].[Q4].[10]` ).
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_mdx_format=>format_date( date = '20261004' time = '133005'
                                                format_string = `["Time"]\.[yyyy]\.["Q"q]\.[m]` )
      exp = `[Time].[2026].[Q4].[10]` ).
    " 1 January 2026 is a Thursday: week 1 is 28 December to 3 January, so 4 October (a Sunday) is in week 41
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_mdx_format=>format_date( date = '20261004' time = '133005'
                                                format_string = `[Ti\me\.Weekl\y]\.[All Ti\me\.Weekl\y\s]\.[yyyy]\.[ww]` )
      exp = `[Time.Weekly].[All Time.Weeklys].[2026].[41]` ).
    " the last days of December are in week 1 of the next year
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_mdx_format=>format_date( date = '20261231' time = '000000' format_string = `ww` )
      exp = `1` ).
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_mdx_format=>format_date( date = '20261004' time = '133005'
                                                format_string = `dddd, mmmm dd yy hh:nn:ss` )
      exp = `Sunday, October 04 26 13:30:05` ).
  ENDMETHOD.

ENDCLASS.