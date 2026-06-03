#ifndef ABC__opt__physical__phyOpt_h
#define ABC__opt__physical__phyOpt_h

#include "base/main/main.h"
#include "opt/physical/phyInfo.h"

ABC_NAMESPACE_HEADER_START

/* shared gate-cost LUT type for physical-aware operators */
typedef struct { float area; float delay; } Phy_GateCostLut_t;

typedef struct Phy_QoR_t_
{
    double Area;
    double Delay;
} Phy_QoR_t;

typedef int (*Phy_EvalQoRFn)( Abc_Frame_t * pAbc, Abc_Ntk_t * pNtk, Phy_QoR_t * pQoR );

extern int Phy_OptRun( Abc_Frame_t * pAbc, Phy_Data_t * pData, int nRounds, int nTop, int fVerbose, int fDynamicOrder, int fAreaOnly, int fBalanced, int nCaseTimeoutSec, double MaxArea, double MaxDelay );
extern int Phy_SetPartitionThresholds( float CritLow, float CritHigh );
extern void Phy_GetPartitionThresholds( float * pCritLow, float * pCritHigh );
extern void Phy_SetEvalQoRFn( Phy_EvalQoRFn pFn );

/* Physical-aware rewrite: guides decomposition with library cell costs */
extern int  Phy_RewriteRun( Abc_Frame_t * pAbc, Abc_Ntk_t * pNtk, Phy_Data_t * pData, int Part, int fVerbose );

/* Physical-aware refactor: rewrite with larger cone windows (5-20 vs 2-10) */
extern int  Phy_RefactorRun( Abc_Frame_t * pAbc, Abc_Ntk_t * pNtk, Phy_Data_t * pData, int Part, int fVerbose );

/* Physical-aware resubstitution: resub using library-aware cost scoring */
extern int  Phy_ResubRun( Abc_Frame_t * pAbc, Abc_Ntk_t * pNtk, Phy_Data_t * pData, int Part, int fVerbose );

/* Physical-aware balance: delay-driven decomposition to recover timing */
extern int  Phy_BalanceRun( Abc_Frame_t * pAbc, Abc_Ntk_t * pNtk, Phy_Data_t * pData, int Part, int fVerbose );

ABC_NAMESPACE_HEADER_END

#endif