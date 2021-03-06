#include <cstdio>
#include <string>
using std::string;

#include "PatchPluto.H"
#include "LoHiSide.H"


#if (EOS != ISOTHERMAL) && (AMR_EN_SWITCH == NO)
 #define REF_VAR  ENG
#else
 #define REF_VAR  RHO
#endif


//#define REF_VAR -1  /* means user-defined */

#define REF_CRIT 1   /* 1 == first derivative, 2 == second derivative */

/* ************************************************************************* */
//void PatchPluto::computeRefGradient(FArrayBox& gFab, FArrayBox& UFab, const Box& b)
void PatchPluto::computeRefGradient(FArrayBox& gFab, FArrayBox& UFab,
                 const FArrayBox& a_dV, const Box& b)

/*
 *
 * PURPOSE
 *
 *   Tag cells for refinement by computing grad[k][j][i]. 
 *   By default a convex combination of the first and second
 *   derivative of the total energy density is used.
 *
 *   REF_CRIT = 1 --> triggers refinement towards the 1st derivative
 *   REF_CRIT = 2 --> triggers refinement towards the 2nd derivative
 *
 * 
 *
 *************************************************************************** */
{
  CH_assert(m_isDefined);

  int nv, i, j, k;
  int Uib, Uie, Ujb=0, Uje=0, Ukb=0, Uke=0;
  int Gib, Gie, Gjb=0, Gje=0, Gkb=0, Gke=0;

  double rp, rm, r;
  double x, dqx_p, dqx_m, dqx, d2qx, den_x;
  double y, dqy_p, dqy_m, dqy, d2qy, den_y;
  double z, dqz_p, dqz_m, dqz, d2qz, den_z;

  double qref, gr1, gr2;

  double eps = 0.1;
  double ***UU[NVAR], ***grad;
  RBox Ubox, Gbox;

  double us[NVAR], vs[NVAR];
  double pm = 0.0, Kin; 
  double **rho, **Bx, **By, dx0,xi,chi_r;

dx0 = 12.8*2/64.0;
  
  rp = rm = r = 1.0;

/* -----------------------------------------------
    The solution array U is defined on the box 
    [Uib, Uie] x [Ujb, Uje] x [Ukb, Uke], which 
    differs from that of gFab ([Gib,...Gke]), 
    typically one point larger in each direction. 
   ----------------------------------------------- */
    
  Ubox.jbeg = Ubox.jend = Ubox.kbeg = Ubox.kend = 0;
  Gbox.jbeg = Gbox.jend = Gbox.kbeg = Gbox.kend = 0;

  DIM_EXPAND(Ubox.ibeg = UFab.loVect()[IDIR]; Ubox.iend = UFab.hiVect()[IDIR]; ,
           Ubox.jbeg = UFab.loVect()[JDIR]; Ubox.jend = UFab.hiVect()[JDIR]; ,
           Ubox.kbeg = UFab.loVect()[KDIR]; Ubox.kend = UFab.hiVect()[KDIR]; );

  DIM_EXPAND(Gbox.ibeg = gFab.loVect()[IDIR]; Gbox.iend = gFab.hiVect()[IDIR]; ,
           Gbox.jbeg = gFab.loVect()[JDIR]; Gbox.jend = gFab.hiVect()[JDIR]; ,
           Gbox.kbeg = gFab.loVect()[KDIR]; Gbox.kend = gFab.hiVect()[KDIR]; );

  for (nv = 0; nv < NVAR; nv++){
    UU[nv] = ArrayBoxMap(Ubox.kbeg, Ubox.kend, 
                         Ubox.jbeg, Ubox.jend, 
                         Ubox.ibeg, Ubox.iend, UFab.dataPtr(nv));
  }
  grad = ArrayBoxMap(Gbox.kbeg, Gbox.kend, 
                     Gbox.jbeg, Gbox.jend, 
                     Gbox.ibeg, Gbox.iend, gFab.dataPtr(0));

/* -- check ref criterion -- */

  #if REF_CRIT != 1 && REF_CRIT != 2
   print ("! TagCells.cpp: Refinement criterion not valid\n");
   QUIT_PLUTO(1);
  #endif

/* -----------------------------------------------
    Main spatial loop for zone tagging based on
    1st (REF_CRIT = 1) or 2nd (REF_CRIT = 2)
    derivative error norm. 
   ----------------------------------------------- */

  Bx  = UU[BX1][0];
  By  = UU[BX2][0];
  rho = UU[RHO][0];
  xi    = fabs(dx0/m_dx - 1.0);
  chi_r = (0.2 - 0.37)/(1.0 + xi*xi) + 0.37;

/* ----------------------------------------------------------------
    Main spatial loop for zone tagging based on 1st (REF_CRIT = 1) 
    or 2nd (REF_CRIT = 2) derivative error norm. 
   ---------------------------------------------------------------- */

  BOX_LOOP(&Gbox, k, j, i){
    z = (k + 0.5)*m_dx + g_domBeg[KDIR];
    y = (j + 0.5)*m_dx + g_domBeg[JDIR];
    x = (i + 0.5)*m_dx + g_domBeg[IDIR];

    #if GEOMETRY == CYLINDRICAL
     rp = (i+0.5)/(i+1.5);
     rm = (i+0.5)/(i-0.5);
    #endif

    dqx = 0.5*(UU[BY][k][j][i+1] - UU[BY][k][j][i-1]);
    dqy = 0.5*(UU[BX][k][j+1][i] - UU[BX][k][j-1][i]);

    pm  = rho[j][i]; 
    gr1 = fabs(dqx - dqy)/(fabs(dqx) + fabs(dqy) + m_dx/dx0*sqrt(pm));
    grad[k][j][i] = gr1/chi_r;
  }

/* --------------------------------------------------------------
    Ok, grad[] has been computed. Now Free memory.
   -------------------------------------------------------------- */
   
  FreeArrayBoxMap(grad, Gbox.kbeg, Gbox.kend,
                        Gbox.jbeg, Gbox.jend,
                        Gbox.ibeg, Gbox.iend);
  for (nv = 0; nv < NVAR; nv++){
    FreeArrayBoxMap(UU[nv], Ubox.kbeg, Ubox.kend,
                            Ubox.jbeg, Ubox.jend,
                            Ubox.ibeg, Ubox.iend);
  }
  #if CHOMBO_REFINEMENT_VAR == -1
   FreeArrayBox(q, Ubox.kbeg, Ubox.jbeg, Ubox.ibeg);
  #endif
}
#undef REF_VAR
#undef REF_CRIT
