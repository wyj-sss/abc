#ifndef ABC__opt__physical__phyOpt_h
#define ABC__opt__physical__phyOpt_h

#include "base/main/main.h"
#include "opt/physical/phyInfo.h"

ABC_NAMESPACE_HEADER_START

extern int Phy_OptRun( Abc_Frame_t * pAbc, Phy_Data_t * pData, int nRounds, int nTop, int fVerbose, int fDynamicOrder, int nCaseTimeoutSec );
extern int Phy_SetPartitionThresholds( float CritLow, float CritHigh );
extern void Phy_GetPartitionThresholds( float * pCritLow, float * pCritHigh );

ABC_NAMESPACE_HEADER_END

#endif