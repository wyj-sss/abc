#ifndef ABC__opt__physical__phyInfo_h
#define ABC__opt__physical__phyInfo_h

#include "base/abc/abc.h"

ABC_NAMESPACE_HEADER_START

typedef struct Phy_NodeInfo_t_
{
    int ObjId;
    char Type[16];
    char NodeName[64];
    int FaninCount;
    char Fanin0[64];
    char Fanin1[64];
    int Fanin0ObjId;
    int Fanin1ObjId;
    int Fanout;
    float Arrival;
    float Required;
    float Slack;
    int Level;
    float Area;
    char GateName[64];
    float Criticality;
    float OptPotentialOrig;
    float OptPotential;
    float StructPotentialRaw;
    float StructPotential;
    float SlackPotentialRaw;
    float SlackPotential;
    float OptPotentialLow;
    float OptPotentialMiddle;
    float OptPotentialHigh;
} Phy_NodeInfo_t;

typedef struct Phy_Data_t_
{
    Vec_Ptr_t * vNodes;
    char FileName[1024];
    float AlphaLow;
    float AlphaMiddle;
    float AlphaHigh;
    float StructWInvChain;
    float StructWPairCollapse;
    float StructWFanoutEase;
    float StructWGateScore;
} Phy_Data_t;

extern Phy_Data_t * Phy_DataReadCsv( const char * pFileName, float AlphaLow, float AlphaMiddle, float AlphaHigh, int fVerbose );
extern void         Phy_DataRecomputePotential( Phy_Data_t * pData, float AlphaLow, float AlphaMiddle, float AlphaHigh, int fVerbose );
extern void         Phy_SetStructRawWeights( float WInvChain, float WPairCollapse, float WFanoutEase, float WGateScore );
extern void         Phy_GetStructRawWeights( float * pWInvChain, float * pWPairCollapse, float * pWFanoutEase, float * pWGateScore );
extern int          Phy_DataWriteCsv( Phy_Data_t * pData, const char * pFileName, int fVerbose );
extern void         Phy_DataFree( Phy_Data_t * pData );
extern void         Phy_DataPrintStats( Phy_Data_t * pData );
extern void         Phy_DataSortByOptPotential( Phy_Data_t * pData, int fDescending );
extern void         Phy_DataSortByOptPotentialLow( Phy_Data_t * pData, int fDescending );
extern void         Phy_DataSortByOptPotentialMiddle( Phy_Data_t * pData, int fDescending );
extern void         Phy_DataSortByOptPotentialHigh( Phy_Data_t * pData, int fDescending );
extern void         Phy_DataSortByCriticality( Phy_Data_t * pData, int fDescending );
extern void         Phy_DataPrintTop( Phy_Data_t * pData, int nTop );

ABC_NAMESPACE_HEADER_END

#endif
