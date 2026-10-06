* abaplint stub of the BW type pool RSD: only the constants used in src/ (names and types; see the system for the
* complete type pool).
TYPE-POOL rsd.
CONSTANTS: BEGIN OF rsd_c_objtp,
             charact   TYPE c LENGTH 3 VALUE 'CHA',
             keyfigure TYPE c LENGTH 3 VALUE 'KYF',
           END OF rsd_c_objtp.
CONSTANTS: BEGIN OF rsd_c_cubetype,
             basic_ic TYPE c LENGTH 1 VALUE 'B',
           END OF rsd_c_cubetype.
