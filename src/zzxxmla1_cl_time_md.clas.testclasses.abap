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
    "! the fiscal years and periods of an interval are its years and months under K4, as variant and key
    METHODS fiscal_values FOR TESTING.
    "! a regular period has its month's dates, the year and FISCPER3; a special period and 000 no dates; a fiscal
    "! year the calendar year's dates
    METHODS fiscal_periods FOR TESTING.
    "! a value of another variant, or no year or period, is none
    METHODS no_fiscal_period FOR TESTING.
    "! a fiscal value is the variant and the key, shown with a /
    METHODS fiscal_value_text FOR TESTING.
    "! a table the system does not have is missing, one it has is not
    METHODS missing_tables FOR TESTING.
    "! a characteristic without SID table is not filled: an error, nothing written
    METHODS fill_without_tables FOR TESTING.
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

  METHOD fiscal_values.
    DATA(interval) = VALUE zzxxmla1_cl_time_md=>ty_interval( from = '20231215' to = '20240210' ).
    DATA(periods) = zzxxmla1_cl_time_md=>values( name = `0FISCPER` interval = interval ).
    cl_abap_unit_assert=>assert_equals( act = lines( periods ) exp = 3 ).
    cl_abap_unit_assert=>assert_equals( act = periods[ 1 ] exp = 'K42023012' ).
    cl_abap_unit_assert=>assert_equals( act = periods[ 3 ] exp = 'K42024002' ).
    DATA(years) = zzxxmla1_cl_time_md=>values( name = `0FISCYEAR` interval = interval ).
    cl_abap_unit_assert=>assert_equals( act = lines( years ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = years[ 1 ] exp = 'K42023' ).
    cl_abap_unit_assert=>assert_equals( act = years[ 2 ] exp = 'K42024' ).
  ENDMETHOD.

  METHOD fiscal_periods.
    DATA(period) = zzxxmla1_cl_time_md=>period( name = `0FISCPER` value = 'K42024002' ).
    cl_abap_unit_assert=>assert_true( period-known ).
    cl_abap_unit_assert=>assert_equals( act = period-from exp = '20240201' ).
    cl_abap_unit_assert=>assert_equals( act = period-to exp = '20240229' ).
    cl_abap_unit_assert=>assert_equals( act = period-year exp = '2024' ).
    cl_abap_unit_assert=>assert_equals( act = period-fiscper3 exp = '002' ).
    period = zzxxmla1_cl_time_md=>period( name = `0FISCPER` value = 'K42024013' ).
    cl_abap_unit_assert=>assert_true( period-known ).
    cl_abap_unit_assert=>assert_initial( period-from ).
    cl_abap_unit_assert=>assert_equals( act = period-fiscper3 exp = '013' ).
    cl_abap_unit_assert=>assert_equals( act = period-year exp = '2024' ).
    period = zzxxmla1_cl_time_md=>period( name = `0FISCPER` value = 'K42024000' ).
    cl_abap_unit_assert=>assert_true( period-known ).
    cl_abap_unit_assert=>assert_initial( period-from ).
    period = zzxxmla1_cl_time_md=>period( name = `0FISCYEAR` value = 'K42024' ).
    cl_abap_unit_assert=>assert_true( period-known ).
    cl_abap_unit_assert=>assert_equals( act = period-from exp = '20240101' ).
    cl_abap_unit_assert=>assert_equals( act = period-to exp = '20241231' ).
    period = zzxxmla1_cl_time_md=>period( name = `0FISCPER` value = 'K42024012' ).
    cl_abap_unit_assert=>assert_equals( act = period-to exp = '20241231' ).
  ENDMETHOD.

  METHOD no_fiscal_period.
    " only K4 is filled: another variant's periods are not its months
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_time_md=>period( name = `0FISCPER` value = 'V32024001' )-known ).
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_time_md=>period( name = `0FISCPER` value = 'K42024' )-known ).
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_time_md=>period( name = `0FISCYEAR` value = 'K42024001' )-known ).
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_time_md=>period( name = `0FISCPER` value = 'K40000001' )-known ).
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_time_md=>period( name = `0FISCPER` value = 'K42024017' )-known ).
  ENDMETHOD.

  METHOD fiscal_value_text.
    DATA(value) = zzxxmla1_cl_time_md=>compound_value( VALUE #( compounding = 'K4' key = '2024001' ) ).
    cl_abap_unit_assert=>assert_equals( act = value exp = 'K42024001' ).
    DATA(characteristics) = zzxxmla1_cl_time_md=>characteristics( ).
    DATA(fiscper) = characteristics[ name = `0FISCPER` ].
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_time_md=>display( characteristic = fiscper value = value )
                                        exp = `K4/2024001` ).
    DATA(calyear) = characteristics[ name = `0CALYEAR` ].
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_time_md=>display( characteristic = calyear value = '1997' )
                                        exp = `1997` ).
  ENDMETHOD.

  METHOD missing_tables.
    DATA(missing) = NEW zzxxmla1_cl_time_md( )->missing_tables(
      VALUE #( name = `0CALYEAR` sid_table = `/BI0/SCALYEAR` attribute_table = `ZZXXMLA1_NO_SUCH_TABLE` ) ).
    cl_abap_unit_assert=>assert_equals( act = missing exp = VALUE string_table( ( `ZZXXMLA1_NO_SUCH_TABLE` ) ) ).
  ENDMETHOD.

  METHOD fill_without_tables.
    DATA(result) = NEW zzxxmla1_cl_time_md( )->fill_characteristic(
      characteristic = VALUE #( name = `0CALYEAR` sid_table = `ZZXXMLA1_NO_SUCH_TABLE` key_field = `CALYEAR` length = 4 )
      interval       = VALUE #( from = '19970101' to = '19971231' calendar = '01' ) ).
    cl_abap_unit_assert=>assert_char_cp( act = result-error exp = `*ZZXXMLA1_NO_SUCH_TABLE does not exist*` ).
    cl_abap_unit_assert=>assert_equals( act = result-created_sids exp = 0 ).
  ENDMETHOD.

ENDCLASS.
