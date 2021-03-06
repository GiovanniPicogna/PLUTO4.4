#define  PHYSICS                        RHD
#define  DIMENSIONS                     2
#define  GEOMETRY                       CYLINDRICAL
#define  BODY_FORCE                     NO
#define  COOLING                        NO
#define  RECONSTRUCTION                 PARABOLIC
#define  TIME_STEPPING                  CHARACTERISTIC_TRACING
#define  NTRACER                        0
#define  PARTICLES                      NO
#define  USER_DEF_PARAMETERS            4

/* -- physics dependent declarations -- */

#define  EOS                            TAUB
#define  ENTROPY_SWITCH                 NO
#define  RADIATION                      NO

/* -- user-defined parameters (labels) -- */

#define  BETA                           0
#define  RHO_IN                         1
#define  RHO_OUT                        2
#define  PRESS_IN                       3

/* [Beg] user-defined constants (do not change this line) */

#define  SHOCK_FLATTENING               MULTID
#define  CHAR_LIMITING                  YES
#define  LIMITER                        MC_LIM
#define  EPS_PSHOCK_FLATTEN             2.5
#define  ARTIFICIAL_VISC                0.1

/* [End] user-defined constants (do not change this line) */
