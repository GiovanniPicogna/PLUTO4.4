/* -----------------------------------------------
             Viscosity header file
   ----------------------------------------------- */

void ViscousFlux (const Data * , double **, double **, double *, int, int, Grid *);
void Visc_nu(double *, double, double, double, double *, double *);
void ViscousRHS (const Data *, Data_Arr, double *, double **, double,
                 int, int, Grid *);


