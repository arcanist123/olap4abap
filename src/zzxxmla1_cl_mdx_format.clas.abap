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
"! Formats numbers with a format string. Understands the digit patterns only (# 0 , .): grouping, minimum
"! integer digits, minimum and maximum decimals, rounding half even as Java's DecimalFormat does. Not yet: sections,
"! literals, percent, currency, styles.
CLASS zzxxmla1_cl_mdx_format DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CLASS-METHODS class_constructor.
    "! The pattern a measure without a format string gets: Java's NumberFormat (en_US), one integer digit at least.
    CONSTANTS c_default TYPE string VALUE `#,##0.###`.

    CLASS-METHODS format
      IMPORTING value         TYPE decfloat34
                pattern       TYPE string DEFAULT c_default
      RETURNING VALUE(result) TYPE string.

    "! Java's Double.toString (JDK 19 and later): the shortest decimal that gives the double back, plain for
    "! 10^-3 <= |value| < 10^7 with at least one decimal (266773.0), else computerized scientific notation (5.6523813E14).
    CLASS-METHODS java_double
      IMPORTING value         TYPE f
      RETURNING VALUE(result) TYPE string.
    "! A double as the text of a Value element: Double.toString without the trailing zeros of a number without
    "! exponent (XmlaUtil.normalizeNumericString).
    CLASS-METHODS xmla_double
      IMPORTING value         TYPE f
      RETURNING VALUE(result) TYPE string.
    "! Format (util.Format, locale en_US) of a double: the format string's sections (positive;
    "! negative;zero;null), number patterns (# 0 . , % with rounding half up of the shortest decimal digits), literals
    "! (quoted, escaped with \, or any character that is no token), < and > (case of the text of a number), predefined
    "! names (Standard, Fixed, Percent, Currency, ...). The empty format string is Java's NumberFormat (#,##0.###).
    "! Not yet: exponents (E+, e-), the text of dates.
    CLASS-METHODS format_number
      IMPORTING value         TYPE f
                format_string TYPE string
      RETURNING VALUE(result) TYPE string.
    "! Format of a string: a string format (with < > and literals) applies, a numeric one does not.
    CLASS-METHODS format_text
      IMPORTING value         TYPE string
                format_string TYPE string
      RETURNING VALUE(result) TYPE string.
    "! Format of a date and time (a Calendar of the default locale, en_US: weeks begin on Sunday, the week
    "! of 1 January is week 1): the date elements of the first section (d dd ddd dddd ddddd dddddd w ww m mm mmm mmmm
    "! q y yy yyyy h hh n nn s ss ttttt) and its literals.
    CLASS-METHODS format_date
      IMPORTING date          TYPE d
                time          TYPE t
                format_string TYPE string
      RETURNING VALUE(result) TYPE string.
    "! Format of null: the fourth section of a numeric format string applied to 0, else empty.
    CLASS-METHODS format_null
      IMPORTING format_string TYPE string
      RETURNING VALUE(result) TYPE string.

  PRIVATE SECTION.
    CONSTANTS:
      BEGIN OF c_flag,
        general TYPE i VALUE 0,
        date    TYPE i VALUE 1,
        numeric TYPE i VALUE 2,
        string  TYPE i VALUE 4,
        special TYPE i VALUE 8,
      END OF c_flag.
    TYPES:
      "! a token of Format.tokens: its code (the name of its FORMAT_ constant), flags and text
      BEGIN OF ty_token,
        code  TYPE string,
        flags TYPE i,
        text  TYPE string,
      END OF ty_token,
      ty_t_token TYPE STANDARD TABLE OF ty_token WITH EMPTY KEY.
    TYPES:
      "! a format element (BasicFormat): LITERAL (with the code of a % or , literal), DATE (writes its token), STRING
      "! (< or >), JAVA (NumberFormat) or NUMERIC (NumericFormat)
      BEGIN OF ty_element,
        kind          TYPE string,
        code          TYPE string,
        text          TYPE string,
        upper         TYPE abap_bool,
        digits_left   TYPE i,
        zeroes_left   TYPE i,
        digits_right  TYPE i,
        zeroes_right  TYPE i,
        use_decimal   TYPE abap_bool,
        use_thou_sep  TYPE abap_bool,
        decimal_shift TYPE i,
        "! the sizes of the digit groups, the last one first and repeated (thousandSeparatorPositions)
        groups        TYPE int4_table,
      END OF ty_element,
      ty_t_element TYPE STANDARD TABLE OF ty_element WITH EMPTY KEY.
    TYPES:
      "! a section (an alternate) of the format string; an absent one (null) has no elements
      BEGIN OF ty_section,
        present  TYPE abap_bool,
        elements TYPE ty_t_element,
      END OF ty_section,
      ty_t_section TYPE STANDARD TABLE OF ty_section WITH EMPTY KEY.
    TYPES:
      "! a parsed format string: JAVA (empty), SINGLE (one date or string section) or ALTERNATE
      BEGIN OF ty_format,
        kind     TYPE string,
        sections TYPE ty_t_section,
      END OF ty_format.
    TYPES:
      "! FloatingDecimal: value = 0.digits * 10^exponent
      BEGIN OF ty_decimal,
        negative TYPE abap_bool,
        digits   TYPE string,
        exponent TYPE i,
      END OF ty_decimal.

    CLASS-DATA tokens TYPE ty_t_token.
    "! the backslash, the escape character of format strings
    CLASS-DATA backslash TYPE string.
    "! the double quote, which encloses literal text in format strings
    CLASS-DATA double_quote TYPE string.

    "! The Format of a format string (constructor and parseFormatString).
    CLASS-METHODS parse
      IMPORTING format_string TYPE string
      RETURNING VALUE(result) TYPE ty_format.
    "! parseFormatString: the first section of the rest of the format string; the rest is changed to what follows it.
    CLASS-METHODS parse_section
      CHANGING rest        TYPE string
               format_type TYPE string
               sections    TYPE ty_t_section.
    "! findToken: the last token of the table the text starts with that suits the format type.
    CLASS-METHODS find_token
      IMPORTING text          TYPE string
                format_type   TYPE string
      RETURNING VALUE(result) TYPE ty_token.
    CLASS-METHODS type_of_flags
      IMPORTING flags         TYPE i
      RETURNING VALUE(result) TYPE string.
    "! MacroToken.expand: the format string of a predefined name.
    CLASS-METHODS expand_macro
      IMPORTING format_string TYPE string
      RETURNING VALUE(result) TYPE string.
    "! fixThousands: a separator right at the end of the integer digits divides by 1000.
    CLASS-METHODS fix_thousands
      IMPORTING rest      TYPE string
      CHANGING  thousands TYPE int4_table
                shift     TYPE i.
    "! The NumericFormat of the digits counted so far.
    CLASS-METHODS numeric_element
      IMPORTING section_text  TYPE string
                digits_left   TYPE i
                zeroes_left   TYPE i
                digits_right  TYPE i
                zeroes_right  TYPE i
                use_decimal   TYPE abap_bool
                use_thou_sep  TYPE abap_bool
      RETURNING VALUE(result) TYPE ty_element.
    CLASS-METHODS format_section
      IMPORTING section       TYPE ty_section
                value         TYPE f
      RETURNING VALUE(result) TYPE string.
    "! AlternateFormat.format(double).
    CLASS-METHODS format_alternate
      IMPORTING format        TYPE ty_format
                value         TYPE f
      RETURNING VALUE(result) TYPE string.
    CLASS-METHODS is_applicable
      IMPORTING section       TYPE ty_section
                value         TYPE f
      RETURNING VALUE(result) TYPE abap_bool.
    "! NumericFormat.format(double).
    CLASS-METHODS format_numeric
      IMPORTING element       TYPE ty_element
                value         TYPE f
      RETURNING VALUE(result) TYPE string.
    "! The digits of the value, shifted by the decimal shift.
    CLASS-METHODS floating_decimal
      IMPORTING value         TYPE f
                shift         TYPE i
      RETURNING VALUE(result) TYPE ty_decimal.
    "! NumericFormat.shows: whether the number shows a digit with that many decimals.
    CLASS-METHODS shows
      IMPORTING decimal       TYPE ty_decimal
                decimals      TYPE i
      RETURNING VALUE(result) TYPE abap_bool.
    "! formatFd2: the digits rounded half up to the maximum decimals, padded to the minimum digits, grouped.
    CLASS-METHODS format_decimal
      IMPORTING decimal       TYPE ty_decimal
                element       TYPE ty_element
      RETURNING VALUE(result) TYPE string.
    "! JavaFormat: NumberFormat.getNumberInstance(US), i.e. #,##0.### rounding half even.
    CLASS-METHODS java_format
      IMPORTING value         TYPE f
      RETURNING VALUE(result) TYPE string.
    "! The shortest digits of a double (as Double.toString) and the exponent of the first: value = d.ddd * 10^exponent.
    CLASS-METHODS shortest_digits
      IMPORTING value    TYPE f
      EXPORTING digits   TYPE string
                exponent TYPE i.
ENDCLASS.

CLASS zzxxmla1_cl_mdx_format IMPLEMENTATION.

  METHOD java_double.
    IF value = 0.
      result = `0.0`.
      RETURN.
    ENDIF.
    " the fewest significant digits that convert back to the same double: d.ddd * 10^exponent
    shortest_digits( EXPORTING value = abs( value ) IMPORTING digits = DATA(digits) exponent = DATA(exponent) ).

    IF exponent >= -3 AND exponent < 7.
      DATA(count) = strlen( digits ).
      IF exponent < 0.
        result = `0.` && repeat( val = `0` occ = - exponent - 1 ) && digits.
      ELSEIF count <= exponent + 1.
        result = digits && repeat( val = `0` occ = exponent + 1 - count ) && `.0`.
      ELSE.
        result = substring( val = digits len = exponent + 1 ) && `.` && substring( val = digits off = exponent + 1 ).
      ENDIF.
    ELSE.
      result = substring( val = digits len = 1 ) && `.`
            && COND #( WHEN strlen( digits ) > 1 THEN substring( val = digits off = 1 ) ELSE `0` ) && |E{ exponent }|.
    ENDIF.
    IF value < 0.
      result = `-` && result.
    ENDIF.
  ENDMETHOD.

  METHOD xmla_double.
    result = java_double( value ).
    IF result CS `.` AND NOT result CS `E`.
      result = shift_right( val = result sub = `0` ).
      IF substring( val = result off = strlen( result ) - 1 len = 1 ) = `.`.
        result = substring( val = result len = strlen( result ) - 1 ).
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD format.
    " a predefined format (Format.java), the empty pattern of a measure without format string
    DATA(effective) = SWITCH string( pattern WHEN `` THEN c_default WHEN `Standard` THEN `#,##0` ELSE pattern ).
    SPLIT effective AT `.` INTO DATA(integer_pattern) DATA(fraction_pattern).
    DATA(grouping) = xsdbool( integer_pattern CS `,` ).
    DATA(min_integer) = count( val = integer_pattern sub = `0` ).
    DATA(max_fraction) = strlen( fraction_pattern ).
    DATA(min_fraction) = count( val = fraction_pattern sub = `0` ).

    DATA(magnitude) = round( val = abs( value ) dec = max_fraction mode = cl_abap_math=>round_half_even ).
    DATA(text) = |{ magnitude DECIMALS = max_fraction }|.
    SPLIT text AT `.` INTO DATA(integer_part) DATA(fraction_part).

    " the decimals beyond the minimum go when they are zeros
    DATA(fraction_length) = strlen( fraction_part ).
    WHILE fraction_length > min_fraction AND substring( val = fraction_part off = fraction_length - 1 len = 1 ) = `0`.
      fraction_length = fraction_length - 1.
    ENDWHILE.
    fraction_part = substring( val = fraction_part len = fraction_length ).

    IF integer_part = `0`.
      integer_part = ``.
    ENDIF.
    WHILE strlen( integer_part ) < min_integer.
      integer_part = `0` && integer_part.
    ENDWHILE.
    IF integer_part IS INITIAL AND fraction_part IS INITIAL.
      integer_part = `0`.
    ENDIF.

    IF grouping = abap_true.
      DATA(grouped) = VALUE string( ).
      DATA(remaining) = strlen( integer_part ).
      DATA(offset) = 0.
      WHILE offset < strlen( integer_part ).
        IF offset > 0 AND remaining MOD 3 = 0.
          grouped = grouped && `,`.
        ENDIF.
        grouped = grouped && substring( val = integer_part off = offset len = 1 ).
        offset = offset + 1.
        remaining = remaining - 1.
      ENDWHILE.
      integer_part = grouped.
    ENDIF.

    result = integer_part.
    IF fraction_part IS NOT INITIAL.
      result = result && `.` && fraction_part.
    ENDIF.
    IF value < 0 AND magnitude <> 0.
      result = `-` && result.
    ENDIF.
  ENDMETHOD.

  METHOD class_constructor.
    " Format.tokens in their order (findToken searches from the end); flags: 1 date, 2 numeric, 4 string, 8 special
    backslash = cl_abap_conv_in_ce=>uccp( '005C' ).
    double_quote = cl_abap_conv_in_ce=>uccp( '0022' ).
    tokens = VALUE #(
      ( code = `C` flags = 1 text = `C` )                 ( code = `D` flags = 1 text = `d` )
      ( code = `DD` flags = 1 text = `dd` )               ( code = `DDD` flags = 1 text = `Ddd` )
      ( code = `DDDD` flags = 1 text = `dddd` )           ( code = `DDDDD` flags = 1 text = `ddddd` )
      ( code = `DDDDDD` flags = 1 text = `dddddd` )       ( code = `W` flags = 1 text = `w` )
      ( code = `WW` flags = 1 text = `ww` )               ( code = `M` flags = 9 text = `m` )
      ( code = `M_UPPER` flags = 1 text = `M` )           ( code = `MM` flags = 9 text = `mm` )
      ( code = `MM_UPPER` flags = 1 text = `MM` )         ( code = `MMM_LOWER` flags = 1 text = `mmm` )
      ( code = `MMMM_LOWER` flags = 1 text = `mmmm` )     ( code = `MMM_UPPER` flags = 1 text = `MMM` )
      ( code = `MMMM_UPPER` flags = 1 text = `MMMM` )     ( code = `Q` flags = 1 text = `q` )
      ( code = `Y` flags = 1 text = `y` )                 ( code = `YY` flags = 1 text = `yy` )
      ( code = `YYYY` flags = 1 text = `yyyy` )           ( code = `H` flags = 1 text = `h` )
      ( code = `HH` flags = 1 text = `hh` )               ( code = `N` flags = 1 text = `n` )
      ( code = `NN` flags = 1 text = `nn` )               ( code = `S` flags = 1 text = `s` )
      ( code = `SS` flags = 1 text = `ss` )               ( code = `TTTTT` flags = 1 text = `ttttt` )
      ( code = `UPPER_AM_SOLIDUS_PM` flags = 1 text = `AM/PM` )
      ( code = `LOWER_AM_SOLIDUS_PM` flags = 1 text = `am/pm` )
      ( code = `UPPER_A_SOLIDUS_P` flags = 1 text = `A/P` )
      ( code = `LOWER_A_SOLIDUS_P` flags = 1 text = `a/p` )
      ( code = `AMPM` flags = 1 text = `AMPM` )           ( code = `ZERO` flags = 10 text = `0` )
      ( code = `POUND` flags = 10 text = `#` )            ( code = `DECIMAL` flags = 10 text = `.` )
      ( code = `PERCENT` flags = 2 text = `%` )           ( code = `THOUSEP` flags = 10 text = `,` )
      ( code = `TIMESEP` flags = 9 text = `:` )           ( code = `DATESEP` flags = 9 text = `/` )
      ( code = `E_MINUS_UPPER` flags = 10 text = `E-` )   ( code = `E_PLUS_UPPER` flags = 10 text = `E+` )
      ( code = `E_MINUS_LOWER` flags = 10 text = `e-` )   ( code = `E_PLUS_LOWER` flags = 10 text = `e+` )
      ( code = `LITERAL` flags = 0 text = `-` )           ( code = `LITERAL` flags = 0 text = `+` )
      ( code = `LITERAL` flags = 0 text = `$` )           ( code = `LITERAL` flags = 0 text = `(` )
      ( code = `LITERAL` flags = 0 text = `)` )           ( code = `LITERAL` flags = 0 text = ` ` )
      ( code = `BACKSLASH` flags = 8 text = backslash )   ( code = `QUOTE` flags = 8 text = double_quote )
      ( code = `CHARACTER_OR_SPACE` flags = 4 text = `@` )
      ( code = `CHARACTER_OR_NOTHING` flags = 4 text = `&` )
      ( code = `LOWER` flags = 12 text = `<` )            ( code = `UPPER` flags = 12 text = `>` )
      ( code = `FILL_FROM_LEFT` flags = 12 text = `!` )   ( code = `SEMI` flags = 8 text = `;` )
      ( code = `USD` flags = 0 text = `USD` )             ( code = `GENERAL_NUMBER` flags = 10 text = `General Number` )
      ( code = `GENERAL_DATE` flags = 9 text = `General Date` )
      ( code = `MMMMM_LOWER` flags = 1 text = `mmmmm` )   ( code = `MMMMM_UPPER` flags = 1 text = `MMMMM` )
      ( code = `HH_UPPER` flags = 1 text = `HH` ) ).
  ENDMETHOD.

  METHOD format_number.
    DATA(format) = parse( format_string ).
    CASE format-kind.
      WHEN `JAVA`.
        result = java_format( value ).
      WHEN `SINGLE`.
        result = format_section( section = format-sections[ 1 ] value = value ).
      WHEN OTHERS.
        result = format_alternate( format = format value = value ).
    ENDCASE.
  ENDMETHOD.

  METHOD format_text.
    " AlternateFormat and JavaFormat write the text as it is
    DATA(format) = parse( format_string ).
    IF format-kind <> `SINGLE`.
      result = value.
      RETURN.
    ENDIF.
    LOOP AT format-sections[ 1 ]-elements INTO DATA(element).
      CASE element-kind.
        WHEN `LITERAL` OR `DATE`.
          result = result && element-text.
        WHEN `STRING`.
          result = result && COND #( WHEN element-upper = abap_true THEN to_upper( value ) ELSE to_lower( value ) ).
        WHEN OTHERS.
          result = result && value.
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.

  METHOD format_date.
    CONSTANTS c_sunday TYPE d VALUE '19000107'.
    DATA(months) = VALUE string_table( ( `January` ) ( `February` ) ( `March` ) ( `April` ) ( `May` ) ( `June` )
                                       ( `July` ) ( `August` ) ( `September` ) ( `October` ) ( `November` )
                                       ( `December` ) ).
    DATA(days) = VALUE string_table( ( `Sunday` ) ( `Monday` ) ( `Tuesday` ) ( `Wednesday` ) ( `Thursday` )
                                     ( `Friday` ) ( `Saturday` ) ).
    DATA(year) = CONV i( date+0(4) ).
    DATA(month) = CONV i( date+4(2) ).
    DATA(day) = CONV i( date+6(2) ).
    DATA(hour) = CONV i( time+0(2) ).
    DATA(minute) = CONV i( time+2(2) ).
    DATA(second) = CONV i( time+4(2) ).
    " Calendar.DAY_OF_WEEK: Sunday 1
    DATA(weekday) = ( date - c_sunday ) MOD 7 + 1.
    DATA(first_of_year) = CONV d( |{ date+0(4) }0101| ).
    DATA(day_of_year) = date - first_of_year + 1.
    " WEEK_OF_YEAR: the week of 1 January is week 1, also at the end of the year before
    DATA(week) = ( day_of_year - 1 + ( first_of_year - c_sunday ) MOD 7 ) DIV 7 + 1.
    DATA(first_of_next_year) = CONV d( |{ year + 1 WIDTH = 4 ALIGN = RIGHT PAD = '0' }0101| ).
    " the Saturday of the week
    DATA(week_end) = CONV d( date + 7 - weekday ).
    IF week_end >= first_of_next_year.
      week = 1.
    ENDIF.
    DATA(format) = parse( format_string ).
    IF format-sections IS INITIAL.
      RETURN.
    ENDIF.
    LOOP AT format-sections[ 1 ]-elements INTO DATA(element).
      CASE element-kind.
        WHEN `LITERAL`.
          result = result && element-text.
        WHEN `DATE`.
          result = result && SWITCH string( element-code
            WHEN `D` THEN |{ day }|
            WHEN `DD` THEN |{ day WIDTH = 2 ALIGN = RIGHT PAD = '0' }|
            WHEN `DDD` THEN substring( val = days[ weekday ] len = 3 )
            WHEN `DDDD` THEN days[ weekday ]
            WHEN `DDDDD` THEN |{ month }/{ day }/{ year MOD 100 WIDTH = 2 ALIGN = RIGHT PAD = '0' }|
            WHEN `DDDDDD` THEN |{ months[ month ] } { day WIDTH = 2 ALIGN = RIGHT PAD = '0' }, { year }|
            WHEN `W` THEN |{ weekday }|
            WHEN `WW` THEN |{ week }|
            WHEN `M` OR `M_UPPER` THEN |{ month }|
            WHEN `MM` OR `MM_UPPER` THEN |{ month WIDTH = 2 ALIGN = RIGHT PAD = '0' }|
            WHEN `MMM_LOWER` OR `MMM_UPPER` THEN substring( val = months[ month ] len = 3 )
            WHEN `MMMM_LOWER` OR `MMMM_UPPER` THEN months[ month ]
            WHEN `Q` THEN |{ ( month - 1 ) DIV 3 + 1 }|
            WHEN `Y` THEN |{ day_of_year }|
            WHEN `YY` THEN |{ year MOD 100 WIDTH = 2 ALIGN = RIGHT PAD = '0' }|
            WHEN `YYYY` THEN |{ year }|
            WHEN `H` THEN |{ hour }|
            WHEN `HH` OR `HH_UPPER` THEN |{ hour WIDTH = 2 ALIGN = RIGHT PAD = '0' }|
            WHEN `N` THEN |{ minute }|
            WHEN `NN` THEN |{ minute WIDTH = 2 ALIGN = RIGHT PAD = '0' }|
            WHEN `S` THEN |{ second }|
            WHEN `SS` THEN |{ second WIDTH = 2 ALIGN = RIGHT PAD = '0' }|
            WHEN `TTTTT` THEN |{ hour }:{ minute WIDTH = 2 ALIGN = RIGHT PAD = '0' }:|
                           && |{ second WIDTH = 2 ALIGN = RIGHT PAD = '0' }|
            ELSE element-text ).
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.

  METHOD format_null.
    DATA(format) = parse( format_string ).
    IF format-kind = `ALTERNATE` AND lines( format-sections ) >= 4.
      IF format-sections[ 4 ]-present = abap_true.
        result = format_section( section = format-sections[ 4 ] value = 0 ).
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD parse.
    DATA(rest) = format_string.
    DATA(format_type) = ``.
    WHILE rest IS NOT INITIAL.
      parse_section( CHANGING rest = rest format_type = format_type sections = result-sections ).
    ENDWHILE.
    IF result-sections IS INITIAL.
      result-kind = `JAVA`.
    ELSEIF result-sections[ 1 ]-present = abap_false.
      result-kind = `JAVA`.
    ELSEIF lines( result-sections ) = 1 AND ( format_type = `DATE` OR format_type = `STRING` ).
      result-kind = `SINGLE`.
    ELSE.
      result-kind = `ALTERNATE`.
    ENDIF.
  ENDMETHOD.

  METHOD parse_section.
    DATA elements TYPE ty_t_element.
    DATA thousands TYPE int4_table.
    DATA element TYPE ty_element.
    DATA(original) = rest.
    DATA(text) = expand_macro( rest ).
    IF substring( val = text off = strlen( text ) - 1 len = 1 ) <> `;`.
      text = text && `;`.
    ENDIF.
    " where we are in a number: 0 not in one, 1 left of the point, 2 right of it, 3 right of an exponent
    DATA(state) = 0.
    DATA(digits_left) = 0.
    DATA(zeroes_left) = 0.
    DATA(digits_right) = 0.
    DATA(zeroes_right) = 0.
    DATA(use_decimal) = abap_false.
    DATA(use_thou_sep) = abap_false.
    DATA(have_seen_number) = abap_false.
    DATA(shift) = 0.

    WHILE text IS NOT INITIAL.
      CLEAR element.
      DATA(next) = ``.
      DATA(token) = find_token( text = text format_type = format_type ).
      IF token-code IS INITIAL.
        " no token: the character is a literal
        element = VALUE #( kind = `LITERAL` text = substring( val = text len = 1 ) ).
        next = substring( val = text off = 1 ).
      ELSE.
        next = substring( val = text off = strlen( token-text ) ).
        IF token-flags DIV 8 MOD 2 = 1.
          CASE token-code.
            WHEN `SEMI`.
              EXIT.
            WHEN `POUND` OR `ZERO`.
              IF state = 0.
                state = 1.
              ENDIF.
              CASE state.
                WHEN 1.
                  IF token-code = `POUND`.
                    digits_left = digits_left + 1.
                  ELSE.
                    zeroes_left = zeroes_left + 1.
                  ENDIF.
                WHEN 2.
                  IF token-code = `POUND`.
                    digits_right = digits_right + 1.
                  ELSE.
                    zeroes_right = zeroes_right + 1.
                  ENDIF.
              ENDCASE.
            WHEN `M` OR `MM`.
              " a minute after an hour, else a month: either way a date element
              element = VALUE #( kind = `DATE` code = token-code text = token-text ).
            WHEN `DECIMAL`.
              IF state = 1.
                fix_thousands( EXPORTING rest = text CHANGING thousands = thousands shift = shift ).
              ENDIF.
              state = 2.
              use_decimal = abap_true.
            WHEN `THOUSEP`.
              IF state = 1.
                use_thou_sep = abap_true.
                APPEND strlen( text ) TO thousands.
              ELSE.
                element = VALUE #( kind = `LITERAL` code = `THOUSEP` text = `,` ).
              ENDIF.
            WHEN `TIMESEP`.
              element = VALUE #( kind = `LITERAL` text = `:` ).
            WHEN `DATESEP`.
              element = VALUE #( kind = `LITERAL` text = `/` ).
            WHEN `BACKSLASH`.
              " the next character as it is
              IF strlen( text ) = 1.
                element = VALUE #( kind = `LITERAL` text = `` ).
                next = ``.
              ELSE.
                element = VALUE #( kind = `LITERAL` text = substring( val = text off = 1 len = 1 ) ).
                next = substring( val = text off = 2 ).
              ENDIF.
            WHEN `E_MINUS_UPPER` OR `E_PLUS_UPPER` OR `E_MINUS_LOWER` OR `E_PLUS_LOWER`.
              " exponents are not implemented: the digits after the E are ignored
              IF state = 1.
                fix_thousands( EXPORTING rest = text CHANGING thousands = thousands shift = shift ).
              ENDIF.
              state = 3.
            WHEN `QUOTE`.
              " the text up to the closing quote, or to the end
              DATA(quoted) = substring( val = text off = 1 ).
              FIND FIRST OCCURRENCE OF double_quote IN quoted MATCH OFFSET DATA(close).
              IF sy-subrc <> 0.
                element = VALUE #( kind = `LITERAL` text = quoted ).
                next = ``.
              ELSE.
                element = VALUE #( kind = `LITERAL` text = substring( val = quoted len = close ) ).
                next = substring( val = quoted off = close + 1 ).
              ENDIF.
            WHEN `UPPER` OR `LOWER`.
              element = VALUE #( kind = `STRING` upper = xsdbool( token-code = `UPPER` ) ).
            WHEN `GENERAL_NUMBER` OR `GENERAL_DATE`.
              element = VALUE #( kind = `JAVA` ).
          ENDCASE.
          IF format_type IS INITIAL.
            format_type = type_of_flags( token-flags ).
          ENDIF.
        ELSE.
          " makeFormat: a date token writes itself (with its code), any other token is a literal (% keeps its code)
          element = VALUE #( kind = COND #( WHEN type_of_flags( token-flags ) = `DATE` THEN `DATE` ELSE `LITERAL` )
                             code = COND #( WHEN token-code = `PERCENT` OR type_of_flags( token-flags ) = `DATE`
                                            THEN token-code )
                             text = token-text ).
        ENDIF.
      ENDIF.

      IF element-kind IS NOT INITIAL.
        IF state <> 0.
          " the number ends at this element
          IF state = 1.
            fix_thousands( EXPORTING rest = text CHANGING thousands = thousands shift = shift ).
          ENDIF.
          APPEND numeric_element( section_text = original digits_left = digits_left zeroes_left = zeroes_left
                                  digits_right = digits_right zeroes_right = zeroes_right
                                  use_decimal = use_decimal use_thou_sep = use_thou_sep ) TO elements.
          state = 0.
          have_seen_number = abap_true.
        ENDIF.
        APPEND element TO elements.
        IF format_type IS INITIAL AND element-kind = `DATE`.
          format_type = `DATE`.
        ENDIF.
      ENDIF.
      text = next.
    ENDWHILE.

    IF state <> 0.
      IF state = 1.
        fix_thousands( EXPORTING rest = text CHANGING thousands = thousands shift = shift ).
      ENDIF.
      APPEND numeric_element( section_text = original digits_left = digits_left zeroes_left = zeroes_left
                              digits_right = digits_right zeroes_right = zeroes_right
                              use_decimal = use_decimal use_thou_sep = use_thou_sep ) TO elements.
      have_seen_number = abap_true.
    ENDIF.
    rest = text.
    IF rest IS NOT INITIAL.
      IF substring( val = rest len = 1 ) = `;`.
        rest = substring( val = rest off = 1 ).
      ENDIF.
    ENDIF.

    " % multiplies by 100; a separator after the number (not before digits) divides by 1000
    DATA(index) = 1.
    WHILE index <= lines( elements ).
      CASE elements[ index ]-code.
        WHEN `PERCENT`.
          shift = shift + 2.
        WHEN `THOUSEP`.
          IF have_seen_number = abap_true AND index < lines( elements ).
            DATA(next_code) = elements[ index + 1 ]-code.
            IF next_code <> `THOUSEP` AND next_code <> `ZERO` AND next_code <> `POUND`.
              WHILE index >= 1.
                IF elements[ index ]-code <> `THOUSEP`.
                  EXIT.
                ENDIF.
                shift = shift - 3.
                DELETE elements INDEX index.
                index = index - 1.
              ENDWHILE.
            ENDIF.
          ENDIF.
      ENDCASE.
      index = index + 1.
    ENDWHILE.
    LOOP AT elements ASSIGNING FIELD-SYMBOL(<element>) WHERE kind = `NUMERIC`.
      <element>-decimal_shift = shift.
    ENDLOOP.
    " adjacent literals merge
    index = 2.
    WHILE index <= lines( elements ).
      IF elements[ index ]-kind = `LITERAL` AND elements[ index - 1 ]-kind = `LITERAL`.
        DATA(merged) = elements[ index - 1 ]-text && elements[ index ]-text.
        elements[ index - 1 ] = VALUE #( kind = `LITERAL` text = merged ).
        DELETE elements INDEX index.
      ELSE.
        index = index + 1.
      ENDIF.
    ENDWHILE.
    APPEND VALUE #( present = xsdbool( elements IS NOT INITIAL ) elements = elements ) TO sections.
  ENDMETHOD.

  METHOD find_token.
    DATA(index) = lines( tokens ).
    WHILE index >= 1.
      DATA(token) = tokens[ index ].
      DATA(length) = strlen( token-text ).
      IF strlen( text ) >= length AND substring( val = text len = length ) = token-text.
        DATA(token_type) = type_of_flags( token-flags ).
        IF format_type IS INITIAL OR token_type IS INITIAL OR token_type = format_type.
          result = token.
          RETURN.
        ENDIF.
      ENDIF.
      index = index - 1.
    ENDWHILE.
  ENDMETHOD.

  METHOD type_of_flags.
    result = COND #( WHEN flags DIV 2 MOD 2 = 1 THEN `NUMERIC`
                     WHEN flags MOD 2 = 1 THEN `DATE`
                     WHEN flags DIV 4 MOD 2 = 1 THEN `STRING` ).
  ENDMETHOD.

  METHOD expand_macro.
    result = SWITCH #( format_string
      WHEN `Currency` THEN `$#,##0.00;($#,##0.00)`
      WHEN `Fixed` THEN `0`
      WHEN `Standard` THEN `#,##0`
      WHEN `Percent` THEN `0.00%`
      WHEN `Scientific` THEN `0.00e+00`
      WHEN `Long Date` THEN `dddd, mmmm dd, yyyy`
      WHEN `Medium Date` THEN `dd-mmm-yy`
      WHEN `Short Date` THEN `m/d/yy`
      WHEN `Long Time` THEN `h:mm:ss AM/PM`
      WHEN `Medium Time` THEN `h:mm AM/PM`
      WHEN `Short Time` THEN `hh:mm`
      WHEN `Yes/No` THEN replace( val = `~Y~e~s;~Y~e~s;~N~o;~N~o` sub = `~` with = backslash occ = 0 )
      WHEN `True/False` THEN replace( val = `~T~r~u~e;~T~r~u~e;~F~a~l~s~e;~F~a~l~s~e` sub = `~` with = backslash
                                      occ = 0 )
      WHEN `On/Off` THEN replace( val = `~O~n;~O~n;~O~f~f;~O~f~f` sub = `~` with = backslash occ = 0 )
      ELSE format_string ).
  ENDMETHOD.

  METHOD fix_thousands.
    DATA(offset) = strlen( rest ) + 1.
    DATA(index) = lines( thousands ).
    WHILE index >= 1.
      thousands[ index ] = thousands[ index ] - offset.
      offset = offset + 1.
      index = index - 1.
    ENDWHILE.
    WHILE thousands IS NOT INITIAL.
      IF thousands[ lines( thousands ) ] <> 0.
        EXIT.
      ENDIF.
      shift = shift - 3.
      DELETE thousands INDEX lines( thousands ).
    ENDWHILE.
  ENDMETHOD.

  METHOD numeric_element.
    result = VALUE #( kind = `NUMERIC` digits_left = digits_left zeroes_left = zeroes_left digits_right = digits_right
                      zeroes_right = zeroes_right use_decimal = use_decimal use_thou_sep = use_thou_sep ).
    " the digit groups of the integer part: with several separators the sizes the format string shows, else 3
    DATA(pattern) = expand_macro( section_text ).
    FIND FIRST OCCURRENCE OF `;` IN pattern MATCH OFFSET DATA(semicolon).
    IF sy-subrc = 0 AND semicolon > 0.
      pattern = substring( val = pattern len = semicolon ).
    ENDIF.
    DATA(separators) = count( val = pattern sub = `,` ).
    IF separators > 1.
      FIND FIRST OCCURRENCE OF `.` IN pattern MATCH OFFSET DATA(point).
      DATA(whole) = COND string( WHEN sy-subrc = 0 THEN substring( val = pattern len = point ) ELSE pattern ).
      SPLIT whole AT `,` INTO TABLE DATA(parts).
      DELETE parts WHERE table_line IS INITIAL.
      DELETE parts INDEX 1.
      DATA(index) = lines( parts ).
      WHILE index >= 1.
        APPEND strlen( parts[ index ] ) TO result-groups.
        index = index - 1.
      ENDWHILE.
    ELSEIF separators = 1.
      result-groups = VALUE #( ( 3 ) ).
    ENDIF.
  ENDMETHOD.

  METHOD format_section.
    LOOP AT section-elements INTO DATA(element).
      CASE element-kind.
        WHEN `LITERAL` OR `DATE`.
          result = result && element-text.
        WHEN `STRING`.
          DATA(text) = java_format( value ).
          result = result && COND #( WHEN element-upper = abap_true THEN to_upper( text ) ELSE to_lower( text ) ).
        WHEN `JAVA`.
          result = result && java_format( value ).
        WHEN `NUMERIC`.
          result = result && format_numeric( element = element value = value ).
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.

  METHOD format_alternate.
    DATA(sections) = format-sections.
    DATA(count) = lines( sections ).
    DATA(number) = value.
    DATA(index) = 1.
    IF number = 0 AND count >= 3 AND sections[ 3 ]-present = abap_true.
      index = 3.
    ELSEIF number < 0.
      IF count >= 2 AND sections[ 2 ]-present = abap_true.
        IF is_applicable( section = sections[ 2 ] value = number ) = abap_true.
          number = - number.
          index = 2.
        ELSEIF count >= 3 AND sections[ 3 ]-present = abap_true.
          " too small for the negative section: the zero section
          index = 3.
        ENDIF.
      ELSEIF is_applicable( section = sections[ 1 ] value = number ) = abap_true.
        " upstream bug 687: the minus goes before the first section's text, but after a leading |
        result = `-` && format_section( section = sections[ 1 ] value = - number ).
        IF strlen( result ) >= 2 AND substring( val = result len = 2 ) = `-|`.
          result = `|-` && substring( val = result off = 2 ).
        ENDIF.
        RETURN.
      ELSE.
        number = 0.
      ENDIF.
    ENDIF.
    result = format_section( section = sections[ index ] value = number ).
  ENDMETHOD.

  METHOD is_applicable.
    result = abap_true.
    IF value >= 0.
      RETURN.
    ENDIF.
    LOOP AT section-elements INTO DATA(element) WHERE kind = `NUMERIC`.
      IF shows( decimal = floating_decimal( value = value shift = element-decimal_shift )
                decimals = element-digits_right + element-zeroes_right ) = abap_false.
        result = abap_false.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD format_numeric.
    DATA(decimal) = floating_decimal( value = value shift = element-decimal_shift ).
    IF value = 0 OR ( value < 0 AND shows( decimal = decimal
                                           decimals = element-digits_right + element-zeroes_right ) = abap_false ).
      " a negative number too small to show: zero, without a minus
      CLEAR decimal.
    ENDIF.
    result = format_decimal( decimal = decimal element = element ).
  ENDMETHOD.

  METHOD floating_decimal.
    IF value = 0.
      RETURN.
    ENDIF.
    result-negative = xsdbool( value < 0 ).
    shortest_digits( EXPORTING value = abs( value ) IMPORTING digits = result-digits exponent = DATA(exponent) ).
    result-exponent = exponent + 1 + shift.
  ENDMETHOD.

  METHOD shows.
    DATA(position) = - decimal-exponent - decimals.
    IF position < 0.
      result = abap_true.
    ELSEIF position = 0 AND decimal-digits IS NOT INITIAL.
      result = xsdbool( substring( val = decimal-digits len = 1 ) >= `5` ).
    ENDIF.
  ENDMETHOD.

  METHOD format_decimal.
    DATA digits TYPE int4_table.
    DATA(count) = strlen( decimal-digits ).
    DATA(min_right) = element-zeroes_right.
    DATA(max_right) = element-zeroes_right + element-digits_right.
    DATA(whole) = nmax( val1 = decimal-exponent val2 = element-zeroes_left ).
    DATA(total) = whole + nmax( val1 = count - decimal-exponent val2 = min_right ).
    DO total TIMES.
      APPEND 0 TO digits.
    ENDDO.
    DO count TIMES.
      digits[ whole - decimal-exponent + sy-index ] = CONV i( substring( val = decimal-digits off = sy-index - 1
                                                                          len = 1 ) ).
    ENDDO.

    " round half up to the maximum decimals
    DATA(last) = whole + max_right.
    IF last < total.
      DATA(m) = total.
      DO.
        m = m - 1.
        IF m < 0.
          " all nines: a new leading 1
          INSERT 1 INTO digits INDEX 1.
          whole = whole + 1.
          total = total + 1.
          last = last + 1.
          EXIT.
        ELSEIF m = last.
          DATA(cut) = digits[ m + 1 ].
          digits[ m + 1 ] = 0.
          IF cut < 5.
            EXIT.
          ENDIF.
        ELSEIF m > last.
          digits[ m + 1 ] = 0.
        ELSEIF digits[ m + 1 ] = 9.
          digits[ m + 1 ] = 0.
        ELSE.
          digits[ m + 1 ] = digits[ m + 1 ] + 1.
          EXIT.
        ENDIF.
      ENDDO.
    ENDIF.

    DATA(first_non_zero) = whole.
    DATA(first_trailing_zero) = 0.
    LOOP AT digits INTO DATA(digit).
      IF digit <> 0.
        first_non_zero = nmin( val1 = first_non_zero val2 = sy-tabix - 1 ).
        first_trailing_zero = sy-tabix.
      ENDIF.
    ENDLOOP.
    DATA(first_print) = nmin( val1 = first_non_zero val2 = whole - element-zeroes_left ).
    DATA(last_print) = nmax( val1 = nmin( val1 = first_trailing_zero val2 = whole + max_right )
                             val2 = whole + min_right ).

    IF decimal-negative = abap_true.
      result = `-`.
    ENDIF.
    IF element-use_thou_sep = abap_true AND element-groups IS NOT INITIAL.
      " from the right: a separator after each group, the last size repeated
      DATA(groups) = element-groups.
      DATA(grouped) = ``.
      DATA(inserted) = 0.
      DATA(j) = whole - 1.
      WHILE j >= first_print.
        IF inserted > 0 AND inserted MOD groups[ 1 ] = 0.
          grouped = `,` && grouped.
          inserted = 0.
          IF lines( groups ) > 1.
            DELETE groups INDEX 1.
          ENDIF.
        ENDIF.
        grouped = |{ digits[ j + 1 ] }| && grouped.
        inserted = inserted + 1.
        j = j - 1.
      ENDWHILE.
      result = result && grouped.
    ELSE.
      j = first_print.
      WHILE j < whole.
        result = result && |{ digits[ j + 1 ] }|.
        j = j + 1.
      ENDWHILE.
    ENDIF.
    IF whole < last_print OR ( element-use_decimal = abap_true AND whole = last_print ).
      result = result && `.`.
    ENDIF.
    j = whole.
    WHILE j < last_print.
      result = result && |{ digits[ j + 1 ] }|.
      j = j + 1.
    ENDWHILE.
  ENDMETHOD.

  METHOD java_format.
    result = format( value = CONV #( value ) pattern = c_default ).
  ENDMETHOD.

  METHOD shortest_digits.
    CLEAR: digits, exponent.
    IF value = 0.
      RETURN.
    ENDIF.
    " the double's value to about 33 digits (CONV decfloat34 keeps only about 17): mantissa * 2^exponent, so that
    " the rounding below picks the decimal nearest to it, as Double.toString does
    DATA(two) = CONV f( 2 ).
    DATA(binary_exponent) = CONV i( floor( log( value ) / log( two ) ) ) - 52.
    DATA(mantissa_f) = value / ipow( base = two exp = binary_exponent ).
    IF mantissa_f >= ipow( base = two exp = 53 ).
      binary_exponent = binary_exponent + 1.
      mantissa_f = value / ipow( base = two exp = binary_exponent ).
    ELSEIF mantissa_f < ipow( base = two exp = 52 ).
      binary_exponent = binary_exponent - 1.
      mantissa_f = value / ipow( base = two exp = binary_exponent ).
    ENDIF.
    " the 53-bit mantissa in two exact halves (a conversion of the whole to an integer is not exact)
    DATA(high) = floor( mantissa_f / ipow( base = two exp = 26 ) ).
    DATA(low) = mantissa_f - high * ipow( base = two exp = 26 ).
    DATA(exact) = ( CONV decfloat34( CONV i( high ) ) * 67108864 + CONV decfloat34( CONV i( low ) ) )
                * ipow( base = CONV decfloat34( 2 ) exp = binary_exponent ).
    DATA(shortest) = exact.
    DO 17 TIMES.
      shortest = round( val = exact prec = sy-index ).
      IF CONV f( shortest ) = value.
        EXIT.
      ENDIF.
    ENDDO.
    DATA(ten) = CONV decfloat34( 10 ).
    exponent = floor( log10( shortest ) ).
    DATA(mantissa) = shortest / ipow( base = ten exp = exponent ).
    IF mantissa >= 10.
      exponent = exponent + 1.
      mantissa = mantissa / 10.
    ELSEIF mantissa < 1.
      exponent = exponent - 1.
      mantissa = mantissa * 10.
    ENDIF.
    DATA scaled TYPE p LENGTH 16 DECIMALS 0.
    scaled = round( val = mantissa * ipow( base = ten exp = 16 ) dec = 0 ).
    digits = shift_right( val = condense( |{ scaled }| ) sub = `0` ).
  ENDMETHOD.

ENDCLASS.