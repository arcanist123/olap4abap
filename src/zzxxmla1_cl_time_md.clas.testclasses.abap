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
"! The values and periods of the time characteristics; nothing is written.
CLASS ltc_time_md DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    "! 1 Monday ... 7 Sunday
    METHODS weekday FOR TESTING.
    "! the ISO week: the year of its Thursday, week 1 the one of 4 January
    METHODS iso_week FOR TESTING.
    "! the months, quarters and years of an interval that starts and ends inside one
    METHODS values_of_interval FOR TESTING.
    "! every week the interval touches, the first one in the year before
    METHODS weeks_of_interval FOR TESTING.
    "! the characteristics without year have all their values
    METHODS values_without_year FOR TESTING.
    "! the periods and the attributes the attribute tables take from them
    METHODS periods FOR TESTING.
    "! a value that is no period has none
    METHODS no_period FOR TESTING.
ENDCLASS.

CLASS zzxxmla1_cl_time_md DEFINITION LOCAL FRIENDS ltc_time_md.

CLASS ltc_time_md IMPLEMENTATION.

  METHOD weekday.
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_time_md=>weekday( '19000101' ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_time_md=>weekday( '19970101' ) exp = 3 ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_time_md=>weekday( '20261004' ) exp = 7 ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_time_md=>weekday( '18991231' ) exp = 7 ).
  ENDMETHOD.

  METHOD iso_week.
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_time_md=>iso_week( '19970101' ) exp = '199701' ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_time_md=>iso_week( '19971231' ) exp = '199801' ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_time_md=>iso_week( '20210103' ) exp = '202053' ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_time_md=>iso_week( '20210104' ) exp = '202101' ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_time_md=>iso_week( '20261007' ) exp = '202641' ).
  ENDMETHOD.

  METHOD values_of_interval.
    DATA(interval) = VALUE zzxxmla1_cl_time_md=>ty_interval( from = '19951001' to = '19970215' ).
    DATA(months) = zzxxmla1_cl_time_md=>values( name = `0CALMONTH` interval = interval ).
    cl_abap_unit_assert=>assert_equals( act = lines( months ) exp = 17 ).
    cl_abap_unit_assert=>assert_equals( act = months[ 1 ] exp = '199510' ).
    cl_abap_unit_assert=>assert_equals( act = months[ 17 ] exp = '199702' ).
    DATA(quarters) = zzxxmla1_cl_time_md=>values( name = `0CALQUARTER` interval = interval ).
    cl_abap_unit_assert=>assert_equals( act = lines( quarters ) exp = 6 ).
    cl_abap_unit_assert=>assert_equals( act = quarters[ 1 ] exp = '19954' ).
    cl_abap_unit_assert=>assert_equals( act = quarters[ 6 ] exp = '19971' ).
    DATA(years) = zzxxmla1_cl_time_md=>values( name = `0CALYEAR` interval = interval ).
    cl_abap_unit_assert=>assert_equals( act = lines( years ) exp = 3 ).
    cl_abap_unit_assert=>assert_equals( act = years[ 3 ] exp = '1997' ).
  ENDMETHOD.

  METHOD weeks_of_interval.
    " 1 January 1997 is a Wednesday of week 1, 31 December 1997 a Wednesday of week 1 of 1998
    DATA(weeks) = zzxxmla1_cl_time_md=>values( name     = `0CALWEEK`
                                               interval = VALUE #( from = '19970101' to = '19971231' ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( weeks ) exp = 53 ).
    cl_abap_unit_assert=>assert_equals( act = weeks[ 1 ] exp = '199701' ).
    cl_abap_unit_assert=>assert_equals( act = weeks[ 52 ] exp = '199752' ).
    cl_abap_unit_assert=>assert_equals( act = weeks[ 53 ] exp = '199801' ).
    " 1 January 2021 is a Friday of week 53 of 2020
    weeks = zzxxmla1_cl_time_md=>values( name = `0CALWEEK` interval = VALUE #( from = '20210101' to = '20210110' ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( weeks ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = weeks[ 1 ] exp = '202053' ).
  ENDMETHOD.

  METHOD values_without_year.
    DATA(interval) = VALUE zzxxmla1_cl_time_md=>ty_interval( from = '19970101' to = '19970131' ).
    DATA(months) = zzxxmla1_cl_time_md=>values( name = `0CALMONTH2` interval = interval ).
    cl_abap_unit_assert=>assert_equals( act = lines( months ) exp = 12 ).
    cl_abap_unit_assert=>assert_equals( act = months[ 1 ] exp = '01' ).
    cl_abap_unit_assert=>assert_equals( act = lines( zzxxmla1_cl_time_md=>values( name = `0CALQUART1` interval = interval ) )
                                        exp = 4 ).
    cl_abap_unit_assert=>assert_equals( act = lines( zzxxmla1_cl_time_md=>values( name = `0HALFYEAR1` interval = interval ) )
                                        exp = 2 ).
    DATA(weekdays) = zzxxmla1_cl_time_md=>values( name = `0WEEKDAY1` interval = interval ).
    cl_abap_unit_assert=>assert_equals( act = lines( weekdays ) exp = 7 ).
    cl_abap_unit_assert=>assert_equals( act = weekdays[ 7 ] exp = '7' ).
  ENDMETHOD.

  METHOD periods.
    DATA(period) = zzxxmla1_cl_time_md=>period( name = `0CALMONTH` value = '199602' ).
    cl_abap_unit_assert=>assert_equals( act = period-from exp = '19960201' ).
    cl_abap_unit_assert=>assert_equals( act = period-to exp = '19960229' ).
    cl_abap_unit_assert=>assert_equals( act = period-year exp = '1996' ).
    cl_abap_unit_assert=>assert_equals( act = period-month2 exp = '02' ).
    period = zzxxmla1_cl_time_md=>period( name = `0CALMONTH` value = '199712' ).
    cl_abap_unit_assert=>assert_equals( act = period-to exp = '19971231' ).
    period = zzxxmla1_cl_time_md=>period( name = `0CALQUARTER` value = '19973' ).
    cl_abap_unit_assert=>assert_equals( act = period-from exp = '19970701' ).
    cl_abap_unit_assert=>assert_equals( act = period-to exp = '19970930' ).
    cl_abap_unit_assert=>assert_equals( act = period-quarter1 exp = '3' ).
    cl_abap_unit_assert=>assert_equals( act = period-year exp = '1997' ).
    period = zzxxmla1_cl_time_md=>period( name = `0CALYEAR` value = '1997' ).
    cl_abap_unit_assert=>assert_equals( act = period-from exp = '19970101' ).
    cl_abap_unit_assert=>assert_equals( act = period-to exp = '19971231' ).
    period = zzxxmla1_cl_time_md=>period( name = `0CALWEEK` value = '199701' ).
    cl_abap_unit_assert=>assert_equals( act = period-from exp = '19961230' ).
    cl_abap_unit_assert=>assert_equals( act = period-to exp = '19970105' ).
    period = zzxxmla1_cl_time_md=>period( name = `0CALWEEK` value = '202053' ).
    cl_abap_unit_assert=>assert_equals( act = period-from exp = '20201228' ).
  ENDMETHOD.

  METHOD no_period.
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_time_md=>period( name = `0CALMONTH` value = '199713' ) ).
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_time_md=>period( name = `0CALQUARTER` value = '19975' ) ).
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_time_md=>period( name = `0CALWEEK` value = '199753' ) ).
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_time_md=>period( name = `0CALMONTH` value = '000000' ) ).
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_time_md=>period( name = `0CALMONTH2` value = '01' ) ).
  ENDMETHOD.

ENDCLASS.
