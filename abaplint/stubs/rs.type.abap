* abaplint stub of the BW type pool RS: only the constants used in src/ (names and types; see the system for the
* complete type pool).
TYPE-POOL rs.
CONSTANTS rs_c_true TYPE c LENGTH 1 VALUE 'X'.
CONSTANTS rs_c_false TYPE c LENGTH 1 VALUE ' '.
CONSTANTS: BEGIN OF rs_c_objvers,
             active   TYPE c LENGTH 1 VALUE 'A',
             modified TYPE c LENGTH 1 VALUE 'M',
             delivery TYPE c LENGTH 1 VALUE 'D',
           END OF rs_c_objvers.
