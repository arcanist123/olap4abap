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
"! MDX token manager: the port of the token manager JavaCC generates from the reference's grammar MdxParser.jj
"! (parser.MdxParserImplTokenManager, options IGNORE_CASE and UNICODE_INPUT), with the line and column counting
"! of JavaCC's SimpleCharStream (a tab moves to the next multiple of 8). As in the reference the input gets a closing newline
"! if it has none. Tokens are read one at a time when the parser asks for one, so that a lexical error comes at the same
"! moment as in the reference. Of the tokens that match, the longest wins, of equally long ones the first declared in the
"! grammar (keywords before identifiers). Kinds are the token names of the grammar (SELECT, ID, QUOTED_ID, LPAREN, ...,
"! EOF at the end). Lexical errors have the text of JavaCC's TokenMgrError.
CLASS zzxxmla1_cl_mdx_token_manager DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_token,
        kind         TYPE string,
        image        TYPE string,
        begin_line   TYPE i,
        begin_column TYPE i,
      END OF ty_token.

    METHODS constructor
      IMPORTING text TYPE string.
    "! The next token; at the end of the input EOF with an empty image, on every further call too.
    METHODS next_token
      RETURNING VALUE(result) TYPE ty_token
      RAISING   zzxxmla1_cx_xmla.

  PRIVATE SECTION.
    TYPES ty_t_int TYPE STANDARD TABLE OF i WITH EMPTY KEY.

    DATA text      TYPE string.
    DATA length    TYPE i.
    DATA position  TYPE i.          " offset of the next character to read
    DATA line_of   TYPE ty_t_int.   " the line of the character at offset n is in row n + 1
    DATA column_of TYPE ty_t_int.
    DATA keywords  TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.

    "! SimpleCharStream.UpdateLineColumn for every character.
    METHODS count_lines.
    "! A comment at the position is skipped (true); an unterminated /* comment is a lexical error.
    METHODS skip_comment
      RETURNING VALUE(result) TYPE abap_bool
      RAISING   zzxxmla1_cx_xmla.
    "! UNSIGNED_INTEGER_LITERAL, DECIMAL_NUMERIC_LITERAL or APPROX_NUMERIC_LITERAL at the offset.
    METHODS match_number
      IMPORTING start  TYPE i
      EXPORTING kind   TYPE string
                length TYPE i.
    "! A string or bracketed name from the opening character at the offset up to the last closing character that ends a
    "! match (a doubled closing character stands for itself). No match: length 0 and kill the offset of the character no
    "! longer allowed (the text length at the end of the input).
    METHODS match_quoted
      IMPORTING start           TYPE i
                closing         TYPE string
                stop_at_newline TYPE abap_bool
      EXPORTING length          TYPE i
                kill            TYPE i.
    "! LETTER (LETTER | DIGIT)* from the offset.
    METHODS match_identifier
      IMPORTING start         TYPE i
      RETURNING VALUE(result) TYPE i.
    "! TokenMgrError for a token begun at start that no pattern matches when the character at kill is read.
    METHODS lexical_error
      IMPORTING start TYPE i
                kill  TYPE i
      RAISING   zzxxmla1_cx_xmla.
    METHODS raise_lexical_error
      IMPORTING message TYPE string
      RAISING   zzxxmla1_cx_xmla.
    "! TokenMgrError.addEscapes.
    METHODS escape
      IMPORTING value         TYPE string
      RETURNING VALUE(result) TYPE string.
    METHODS char_at
      IMPORTING offset        TYPE i
      RETURNING VALUE(result) TYPE string.
    METHODS code_at
      IMPORTING offset        TYPE i
      RETURNING VALUE(result) TYPE i.
    METHODS is_white
      IMPORTING offset        TYPE i
      RETURNING VALUE(result) TYPE abap_bool.
    METHODS is_ascii_digit
      IMPORTING offset        TYPE i
      RETURNING VALUE(result) TYPE abap_bool.
    "! LETTER of the grammar.
    METHODS is_letter
      IMPORTING offset        TYPE i
      RETURNING VALUE(result) TYPE abap_bool.
    "! DIGIT of the grammar (Unicode digits of several scripts).
    METHODS is_digit
      IMPORTING offset        TYPE i
      RETURNING VALUE(result) TYPE abap_bool.
ENDCLASS.

CLASS zzxxmla1_cl_mdx_token_manager IMPLEMENTATION.

  METHOD constructor.
    me->text = text.
    " MdxParserImpl.term: the parser always reads a closing newline
    IF strlen( me->text ) = 0
        OR substring( val = me->text off = strlen( me->text ) - 1 len = 1 ) <> cl_abap_char_utilities=>newline.
      me->text = me->text && cl_abap_char_utilities=>newline.
    ENDIF.
    length = strlen( me->text ).
    count_lines( ).
    " the keywords and reserved words of the grammar
    DATA(words) = `AND AS AXIS BEGIN BY CASE CAST CELL CHAPTERS CREATE COLUMNS COMMIT CUBE DIMENSION DRILLTHROUGH ELSE `
               && `EMPTY END EXPLAIN FIRSTROWSET FOR FROM IN IS MATCHES MAXROWS MEMBER NON NOT NULL ON OR PAGES PLAN `
               && `PROPERTIES REFRESH RETURN ROLLBACK ROWS SECTIONS SELECT SESSION SET THEN TRAN TRANSACTION UPDATE `
               && `USE_EQUAL_ALLOCATION USE_EQUAL_INCREMENT USE_WEIGHTED_ALLOCATION USE_WEIGHTED_INCREMENT WHEN WHERE `
               && `XOR WITH EXISTING $SYSTEM`.
    SPLIT words AT ` ` INTO TABLE DATA(word_list).
    keywords = word_list.
  ENDMETHOD.

  METHOD count_lines.
    DATA(cr) = cl_abap_char_utilities=>cr_lf(1).
    DATA(lf) = cl_abap_char_utilities=>newline.
    DATA(line) = 1.
    DATA(column) = 0.
    DATA(previous_lf) = abap_false.
    DATA(previous_cr) = abap_false.
    DO length TIMES.
      DATA(c) = char_at( sy-index - 1 ).
      column = column + 1.
      IF previous_lf = abap_true.
        previous_lf = abap_false.
        line = line + 1.
        column = 1.
      ELSEIF previous_cr = abap_true.
        previous_cr = abap_false.
        IF c = lf.
          previous_lf = abap_true.
        ELSE.
          line = line + 1.
          column = 1.
        ENDIF.
      ENDIF.
      IF c = cr.
        previous_cr = abap_true.
      ELSEIF c = lf.
        previous_lf = abap_true.
      ELSEIF c = cl_abap_char_utilities=>horizontal_tab.
        column = column - 1.
        column = column + ( 8 - column MOD 8 ).
      ENDIF.
      APPEND line TO line_of.
      APPEND column TO column_of.
    ENDDO.
  ENDMETHOD.

  METHOD next_token.
    DO.
      WHILE position < length AND is_white( position ) = abap_true.
        position = position + 1.
      ENDWHILE.
      IF position >= length.
        " EOF begins at the last character read
        result = VALUE #( kind = `EOF` begin_line = line_of[ length ] begin_column = column_of[ length ] ).
        RETURN.
      ENDIF.
      IF skip_comment( ) = abap_false.
        EXIT.
      ENDIF.
    ENDDO.

    DATA(start) = position.
    DATA(c) = char_at( start ).
    DATA(next) = char_at( start + 1 ).
    DATA(kind) = ``.
    DATA(size) = 0.
    DATA(kill) = start.
    IF is_ascii_digit( start ) = abap_true OR ( c = `.` AND is_ascii_digit( start + 1 ) = abap_true ).
      match_number( EXPORTING start = start IMPORTING kind = kind length = size ).
    ELSEIF c = `'` OR c = `"`.
      match_quoted( EXPORTING start = start closing = c stop_at_newline = abap_false IMPORTING length = size kill = kill ).
      kind = COND #( WHEN c = `'` THEN `SINGLE_QUOTED_STRING` ELSE `DOUBLE_QUOTED_STRING` ).
    ELSEIF c = `[`.
      match_quoted( EXPORTING start = start closing = `]` stop_at_newline = abap_true IMPORTING length = size kill = kill ).
      kind = `QUOTED_ID`.
    ELSEIF c = `&`.
      IF next = `[`.
        match_quoted( EXPORTING start = start + 1 closing = `]` stop_at_newline = abap_true
                      IMPORTING length = size kill = kill ).
        IF size > 0.
          size = size + 1.
        ENDIF.
        kind = `AMP_QUOTED_ID`.
      ELSEIF next IS NOT INITIAL AND to_upper( next ) BETWEEN `A` AND `Z`.
        size = 1 + match_identifier( start + 1 ).
        kind = `AMP_UNQUOTED_ID`.
      ELSE.
        kill = start + 1.
      ENDIF.
    ELSEIF is_letter( start ) = abap_true.
      size = match_identifier( start ).
      DATA(word) = to_upper( substring( val = text off = start len = size ) ).
      kind = COND #( WHEN line_exists( keywords[ table_line = word ] ) THEN word ELSE `ID` ).
    ELSE.
      size = 2.
      CASE c && next.
        WHEN `||`.
          kind = `CONCAT`.
        WHEN `>=`.
          kind = `GE`.
        WHEN `<=`.
          kind = `LE`.
        WHEN `<>`.
          kind = `NE`.
        WHEN OTHERS.
          size = 1.
          CASE c.
            WHEN `*`.
              kind = `ASTERISK`.
            WHEN `!`.
              kind = `BANG`.
            WHEN `:`.
              kind = `COLON`.
            WHEN `,`.
              kind = `COMMA`.
            WHEN `.`.
              kind = `DOT`.
            WHEN `=`.
              kind = `EQ`.
            WHEN `>`.
              kind = `GT`.
            WHEN `{`.
              kind = `LBRACE`.
            WHEN `(`.
              kind = `LPAREN`.
            WHEN `<`.
              kind = `LT`.
            WHEN `-`.
              kind = `MINUS`.
            WHEN `+`.
              kind = `PLUS`.
            WHEN `}`.
              kind = `RBRACE`.
            WHEN `)`.
              kind = `RPAREN`.
            WHEN `/`.
              kind = `SOLIDUS`.
            WHEN `@`.
              kind = `ATSIGN`.
            WHEN `|`.
              " only the start of ||
              size = 0.
              kill = start + 1.
            WHEN OTHERS.
              size = 0.
          ENDCASE.
      ENDCASE.
    ENDIF.
    IF size = 0.
      lexical_error( start = start kill = kill ).
    ENDIF.

    result = VALUE #( kind = kind image = substring( val = text off = start len = size )
                      begin_line = line_of[ start + 1 ] begin_column = column_of[ start + 1 ] ).
    position = start + size.
  ENDMETHOD.

  METHOD skip_comment.
    DATA(cr) = cl_abap_char_utilities=>cr_lf(1).
    DATA(lf) = cl_abap_char_utilities=>newline.
    DATA(start) = position.
    DATA(two) = substring( val = text off = start len = nmin( val1 = 2 val2 = length - start ) ).
    DATA(from) = 0.
    IF two = `/*` AND char_at( start + 2 ) = `*` AND start + 3 < length AND char_at( start + 3 ) <> `/`.
      " <"/**" ~["/"]> : IN_FORMAL_COMMENT
      from = start + 4.
    ELSEIF two = `//` OR two = `--`.
      " to the end of the line: \n, \r or \r\n
      DATA(i) = start + 2.
      WHILE i < length AND char_at( i ) <> lf AND char_at( i ) <> cr.
        i = i + 1.
      ENDWHILE.
      IF char_at( i ) = cr AND char_at( i + 1 ) = lf.
        i = i + 1.
      ENDIF.
      position = i + 1.
      result = abap_true.
      RETURN.
    ELSEIF two = `/*`.
      from = start + 2.
    ELSE.
      RETURN.
    ENDIF.

    " to the next */
    i = from.
    WHILE i + 1 < length AND substring( val = text off = i len = 2 ) <> `*/`.
      i = i + 1.
    ENDWHILE.
    IF i + 1 >= length.
      raise_lexical_error( |Lexical error at line { line_of[ length ] + 1 }, column 0.  Encountered: <EOF> after : ""| ).
    ENDIF.
    position = i + 2.
    result = abap_true.
  ENDMETHOD.

  METHOD match_number.
    DATA(i) = start.
    WHILE is_ascii_digit( i ) = abap_true.
      i = i + 1.
    ENDWHILE.
    kind = `UNSIGNED_INTEGER_LITERAL`.
    IF char_at( i ) = `.`.
      i = i + 1.
      WHILE is_ascii_digit( i ) = abap_true.
        i = i + 1.
      ENDWHILE.
      kind = `DECIMAL_NUMERIC_LITERAL`.
    ENDIF.
    " EXPONENT: ["e","E"] (["+","-"])? (["0"-"9"])+
    IF char_at( i ) = `e` OR char_at( i ) = `E`.
      DATA(j) = i + 1.
      IF char_at( j ) = `+` OR char_at( j ) = `-`.
        j = j + 1.
      ENDIF.
      IF is_ascii_digit( j ) = abap_true.
        WHILE is_ascii_digit( j ) = abap_true.
          j = j + 1.
        ENDWHILE.
        i = j.
        kind = `APPROX_NUMERIC_LITERAL`.
      ENDIF.
    ENDIF.
    length = i - start.
  ENDMETHOD.

  METHOD match_quoted.
    DATA(cr) = cl_abap_char_utilities=>cr_lf(1).
    DATA(lf) = cl_abap_char_utilities=>newline.
    DATA(i) = start + 1.
    DATA(accept) = -1.
    DO.
      IF i >= me->length.
        kill = me->length.
        EXIT.
      ENDIF.
      DATA(c) = char_at( i ).
      IF c = closing.
        accept = i.
        IF char_at( i + 1 ) = closing.
          i = i + 2.
          CONTINUE.
        ENDIF.
        EXIT.
      ELSEIF stop_at_newline = abap_true AND ( c = lf OR c = cr ).
        kill = i.
        EXIT.
      ENDIF.
      i = i + 1.
    ENDDO.
    length = COND #( WHEN accept >= 0 THEN accept - start + 1 ELSE 0 ).
  ENDMETHOD.

  METHOD match_identifier.
    DATA(i) = start + 1.
    WHILE i < length AND ( is_letter( i ) = abap_true OR is_digit( i ) = abap_true ).
      i = i + 1.
    ENDWHILE.
    result = i - start.
  ENDMETHOD.

  METHOD lexical_error.
    " the input ends with a newline, so reading on from the last character is the end of the input
    DATA(last) = length - 1.
    IF kill >= last.
      DATA(count) = last - start + 1.
      DATA(after) = COND string( WHEN count > 1 THEN substring( val = text off = start len = count ) ).
      raise_lexical_error(
        |Lexical error at line { line_of[ length ] + 1 }, column 0.  Encountered: <EOF> after : "{ escape( after ) }"| ).
    ENDIF.
    after = COND #( WHEN kill > start THEN substring( val = text off = start len = kill - start ) ).
    raise_lexical_error( |Lexical error at line { line_of[ kill + 1 ] }, column { column_of[ kill + 1 ] }.  | &&
                         |Encountered: "{ escape( char_at( kill ) ) }" ({ code_at( kill ) }), after : "{ escape( after ) }"| ).
  ENDMETHOD.

  METHOD raise_lexical_error.
    zzxxmla1_cx_xmla=>raise_code( kind = `Server` code = `00UE001` text = `Internal Error`
                                  description = message ).
  ENDMETHOD.

  METHOD escape.
    CONSTANTS hex TYPE string VALUE `0123456789abcdef`.
    DO strlen( value ) TIMES.
      DATA(offset) = sy-index - 1.
      DATA(c) = substring( val = value off = offset len = 1 ).
      DATA(code) = cl_abap_conv_out_ce=>uccpi( CONV char1( c ) ).
      CASE code.
        WHEN 0.
          CONTINUE.
        WHEN 8.
          result = result && `\b`.
        WHEN 9.
          result = result && `\t`.
        WHEN 10.
          result = result && `\n`.
        WHEN 12.
          result = result && `\f`.
        WHEN 13.
          result = result && `\r`.
        WHEN 34.
          result = result && `\"`.
        WHEN 39.
          result = result && `\'`.
        WHEN 92.
          result = result && `\\`.
        WHEN OTHERS.
          IF code < 32 OR code > 126.
            result = result && `\u` && substring( val = hex off = code DIV 4096 len = 1 )
                     && substring( val = hex off = code DIV 256 MOD 16 len = 1 )
                     && substring( val = hex off = code DIV 16 MOD 16 len = 1 )
                     && substring( val = hex off = code MOD 16 len = 1 ).
          ELSE.
            result = result && c.
          ENDIF.
      ENDCASE.
    ENDDO.
  ENDMETHOD.

  METHOD char_at.
    IF offset >= 0 AND offset < strlen( text ).
      result = substring( val = text off = offset len = 1 ).
    ENDIF.
  ENDMETHOD.

  METHOD code_at.
    result = cl_abap_conv_out_ce=>uccpi( CONV char1( char_at( offset ) ) ).
  ENDMETHOD.

  METHOD is_white.
    DATA(c) = char_at( offset ).
    result = xsdbool( c = ` ` OR c = cl_abap_char_utilities=>horizontal_tab OR c = cl_abap_char_utilities=>newline
                      OR c = cl_abap_char_utilities=>cr_lf(1) OR c = cl_abap_char_utilities=>form_feed ).
  ENDMETHOD.

  METHOD is_ascii_digit.
    DATA(c) = char_at( offset ).
    result = xsdbool( c IS NOT INITIAL AND c CO `0123456789` ).
  ENDMETHOD.

  METHOD is_letter.
    IF offset < 0 OR offset >= length.
      RETURN.
    ENDIF.
    DATA(code) = code_at( offset ).
    result = xsdbool( code = 36 OR code BETWEEN 65 AND 90 OR code = 95 OR code BETWEEN 97 AND 122
                      OR code BETWEEN 192 AND 214 OR code BETWEEN 216 AND 246 OR code BETWEEN 248 AND 255
                      OR code BETWEEN 256 AND 8191 OR code BETWEEN 12352 AND 12687 OR code BETWEEN 13056 AND 13183
                      OR code BETWEEN 13312 AND 15661 OR code BETWEEN 19968 AND 40959 OR code BETWEEN 63744 AND 64255 ).
  ENDMETHOD.

  METHOD is_digit.
    IF offset < 0 OR offset >= length.
      RETURN.
    ENDIF.
    DATA(code) = code_at( offset ).
    result = xsdbool( code BETWEEN 48 AND 57 OR code BETWEEN 1632 AND 1641 OR code BETWEEN 1776 AND 1785
                      OR code BETWEEN 2406 AND 2415 OR code BETWEEN 2534 AND 2543 OR code BETWEEN 2662 AND 2671
                      OR code BETWEEN 2790 AND 2799 OR code BETWEEN 2918 AND 2927 OR code BETWEEN 3047 AND 3055
                      OR code BETWEEN 3174 AND 3183 OR code BETWEEN 3302 AND 3311 OR code BETWEEN 3430 AND 3439
                      OR code BETWEEN 3664 AND 3673 OR code BETWEEN 3792 AND 3801 OR code BETWEEN 4160 AND 4169 ).
  ENDMETHOD.

ENDCLASS.