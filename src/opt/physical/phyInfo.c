#include "phyInfo.h"

ABC_NAMESPACE_IMPL_START

static int s_PhySortDescending = 1;

static int Phy_ParseCsvFields( char * pLine, char * pFields[], int nFieldsMax )
{
    int nFields = 0;
    char * p = pLine;
    char * pStart = pLine;
    while ( *p && nFields < nFieldsMax )
    {
        if ( *p == ',' )
        {
            *p = '\0';
            pFields[nFields++] = pStart;
            pStart = p + 1;
        }
        p++;
    }
    if ( nFields < nFieldsMax )
        pFields[nFields++] = pStart;
    return nFields;
}

static void Phy_StrCopy( char * pDst, int nDst, const char * pSrc )
{
    int i;
    if ( pSrc == NULL )
    {
        pDst[0] = '\0';
        return;
    }
    for ( i = 0; i < nDst - 1 && pSrc[i] != '\0'; i++ )
        pDst[i] = pSrc[i];
    pDst[i] = '\0';
}

static int Phy_LineIsEmpty( const char * pLine )
{
    while ( *pLine )
    {
        if ( *pLine != ' ' && *pLine != '\t' && *pLine != '\r' && *pLine != '\n' )
            return 0;
        pLine++;
    }
    return 1;
}

static int Phy_FieldIsInteger( const char * pField )
{
    const char * p = pField;
    if ( p == NULL || *p == '\0' )
        return 0;
    if ( *p == '+' || *p == '-' )
        p++;
    if ( *p == '\0' )
        return 0;
    while ( *p )
    {
        if ( *p < '0' || *p > '9' )
            return 0;
        p++;
    }
    return 1;
}

static Phy_NodeInfo_t * Phy_NodeInfoParse( char * pLine )
{
    char * pFields[32];
    Phy_NodeInfo_t * pInfo;
    int nFields;
    int fHasTailIds = 0;

    nFields = Phy_ParseCsvFields( pLine, pFields, 32 );
    if ( nFields < 15 )
        return NULL;

    pInfo = ABC_CALLOC( Phy_NodeInfo_t, 1 );
    pInfo->ObjId = atoi( pFields[0] );
    Phy_StrCopy( pInfo->Type, sizeof(pInfo->Type), pFields[1] );
    Phy_StrCopy( pInfo->NodeName, sizeof(pInfo->NodeName), pFields[2] );
    pInfo->FaninCount = atoi( pFields[3] );
    Phy_StrCopy( pInfo->Fanin0, sizeof(pInfo->Fanin0), pFields[4] );
    Phy_StrCopy( pInfo->Fanin1, sizeof(pInfo->Fanin1), pFields[5] );
    pInfo->Fanin0ObjId = -1;
    pInfo->Fanin1ObjId = -1;
    pInfo->Fanout = atoi( pFields[6] );
    pInfo->Arrival = (float)atof( pFields[7] );
    pInfo->Required = (float)atof( pFields[8] );
    pInfo->Slack = (float)atof( pFields[9] );
    pInfo->Level = atoi( pFields[10] );
    pInfo->Area = (float)atof( pFields[11] );
    Phy_StrCopy( pInfo->GateName, sizeof(pInfo->GateName), pFields[12] );
    pInfo->Criticality = (float)atof( pFields[13] );
    pInfo->OptPotentialOrig = (float)atof( pFields[14] );
    pInfo->OptPotential = pInfo->OptPotentialOrig;

    fHasTailIds = (nFields >= 17) && Phy_FieldIsInteger( pFields[nFields - 2] ) && Phy_FieldIsInteger( pFields[nFields - 1] );

    if ( nFields >= 23 && fHasTailIds )
    {
        pInfo->StructPotentialRaw = (float)atof( pFields[15] );
        pInfo->StructPotential = (float)atof( pFields[16] );
        pInfo->SlackPotential = (float)atof( pFields[17] );
        pInfo->OptPotentialLow = (float)atof( pFields[18] );
        pInfo->OptPotentialMiddle = (float)atof( pFields[19] );
        pInfo->OptPotentialHigh = (float)atof( pFields[20] );
        pInfo->OptPotential = pInfo->OptPotentialMiddle;
        pInfo->Fanin0ObjId = atoi( pFields[21] );
        pInfo->Fanin1ObjId = atoi( pFields[22] );
    }
    else if ( nFields >= 21 && !fHasTailIds )
    {
        pInfo->StructPotentialRaw = (float)atof( pFields[15] );
        pInfo->StructPotential = (float)atof( pFields[16] );
        pInfo->SlackPotential = (float)atof( pFields[17] );
        pInfo->OptPotentialLow = (float)atof( pFields[18] );
        pInfo->OptPotentialMiddle = (float)atof( pFields[19] );
        pInfo->OptPotentialHigh = (float)atof( pFields[20] );
        pInfo->OptPotential = pInfo->OptPotentialMiddle;
    }
    else if ( nFields >= 19 )
    {
        pInfo->StructPotentialRaw = (float)atof( pFields[15] );
        pInfo->StructPotential = (float)atof( pFields[16] );
        pInfo->SlackPotential = (float)atof( pFields[17] );
        pInfo->OptPotentialMiddle = (float)atof( pFields[18] );
        pInfo->OptPotential = pInfo->OptPotentialMiddle;
    }
    if ( fHasTailIds && !(nFields >= 23) )
    {
        pInfo->Fanin0ObjId = atoi( pFields[nFields - 2] );
        pInfo->Fanin1ObjId = atoi( pFields[nFields - 1] );
    }
    return pInfo;
}

static float Phy_FltClamp01( float x )
{
    if ( x < 0.0f ) return 0.0f;
    if ( x > 1.0f ) return 1.0f;
    return x;
}

static int Phy_GateStartsWith( const char * pName, const char * pPref )
{
    int i;
    for ( i = 0; pPref[i] != '\0'; i++ )
        if ( pName[i] != pPref[i] )
            return 0;
    return 1;
}

static float Phy_StructPotentialRaw( const Phy_NodeInfo_t * p )
{
    float gateScore, fanoutEase, invChainProxy, pairCollapseProxy;

    if ( Phy_GateStartsWith( p->GateName, "INV" ) )
        gateScore = 1.0f;
    else if ( Phy_GateStartsWith( p->GateName, "NAND" ) || Phy_GateStartsWith( p->GateName, "AND" ) )
        gateScore = 0.7f;
    else
        gateScore = 0.3f;

    fanoutEase = 1.0f / (1.0f + (float)(p->Fanout < 0 ? 0 : p->Fanout));
    invChainProxy = (Phy_GateStartsWith( p->GateName, "INV" ) && p->FaninCount == 1 && p->Fanout <= 1) ? 1.0f : 0.0f;
    pairCollapseProxy = ((Phy_GateStartsWith( p->GateName, "NAND" ) || Phy_GateStartsWith( p->GateName, "AND" )) && p->FaninCount == 2 && p->Fanout <= 2) ? 1.0f : 0.0f;

    return 0.40f * invChainProxy + 0.30f * pairCollapseProxy + 0.20f * fanoutEase + 0.10f * gateScore;
}

void Phy_DataRecomputePotential( Phy_Data_t * pData, float AlphaLow, float AlphaMiddle, float AlphaHigh, int fVerbose )
{
    Phy_NodeInfo_t * pInfo;
    int i;
    float MinStruct = 1e30f, MaxStruct = -1e30f;
    float MinSlack  = 1e30f, MaxSlack  = -1e30f;
    float SumStruct = 0.0f, SumSlack = 0.0f, SumOpt = 0.0f;

    if ( pData == NULL || pData->vNodes == NULL )
        return;

    AlphaLow = Phy_FltClamp01( AlphaLow );
    AlphaMiddle = Phy_FltClamp01( AlphaMiddle );
    AlphaHigh = Phy_FltClamp01( AlphaHigh );
    pData->AlphaLow = AlphaLow;
    pData->AlphaMiddle = AlphaMiddle;
    pData->AlphaHigh = AlphaHigh;

    Vec_PtrForEachEntry( Phy_NodeInfo_t *, pData->vNodes, pInfo, i )
    {
        pInfo->StructPotentialRaw = Phy_StructPotentialRaw( pInfo );
        pInfo->SlackPotentialRaw = pInfo->Slack;
        if ( pInfo->StructPotentialRaw < MinStruct ) MinStruct = pInfo->StructPotentialRaw;
        if ( pInfo->StructPotentialRaw > MaxStruct ) MaxStruct = pInfo->StructPotentialRaw;
        if ( pInfo->SlackPotentialRaw < MinSlack ) MinSlack = pInfo->SlackPotentialRaw;
        if ( pInfo->SlackPotentialRaw > MaxSlack ) MaxSlack = pInfo->SlackPotentialRaw;
    }

    Vec_PtrForEachEntry( Phy_NodeInfo_t *, pData->vNodes, pInfo, i )
    {
        if ( MaxStruct - MinStruct < 1e-12f )
            pInfo->StructPotential = 0.0f;
        else
            pInfo->StructPotential = (pInfo->StructPotentialRaw - MinStruct) / (MaxStruct - MinStruct);

        if ( MaxSlack - MinSlack < 1e-12f )
            pInfo->SlackPotential = 0.0f;
        else
            pInfo->SlackPotential = (pInfo->SlackPotentialRaw - MinSlack) / (MaxSlack - MinSlack);

        pInfo->OptPotentialLow = AlphaLow * pInfo->SlackPotential + (1.0f - AlphaLow) * pInfo->StructPotential;
        pInfo->OptPotentialMiddle = AlphaMiddle * pInfo->SlackPotential + (1.0f - AlphaMiddle) * pInfo->StructPotential;
        pInfo->OptPotentialHigh = AlphaHigh * pInfo->SlackPotential + (1.0f - AlphaHigh) * pInfo->StructPotential;
        pInfo->OptPotential = pInfo->OptPotentialMiddle;

        SumStruct += pInfo->StructPotential;
        SumSlack += pInfo->SlackPotential;
        SumOpt += pInfo->OptPotentialMiddle;
    }

    if ( fVerbose && Vec_PtrSize(pData->vNodes) > 0 )
    {
        float nInv = 1.0f / (float)Vec_PtrSize(pData->vNodes);
        Abc_Print( 1, "Potential rebuilt: alpha(low/mid/high)=%.3f/%.3f/%.3f avg_struct=%.4f avg_slack=%.4f avg_opt_mid=%.4f\n",
            AlphaLow, AlphaMiddle, AlphaHigh, SumStruct * nInv, SumSlack * nInv, SumOpt * nInv );
    }
}

Phy_Data_t * Phy_DataReadCsv( const char * pFileName, float AlphaLow, float AlphaMiddle, float AlphaHigh, int fVerbose )
{
    Phy_Data_t * pData;
    FILE * pFile;
    char Buffer[4096];
    int nLines = 0;

    pFile = fopen( pFileName, "r" );
    if ( pFile == NULL )
    {
        Abc_Print( -1, "Cannot open physical info file: %s\n", pFileName );
        return NULL;
    }

    pData = ABC_CALLOC( Phy_Data_t, 1 );
    pData->vNodes = Vec_PtrAlloc( 1024 );
    Phy_StrCopy( pData->FileName, sizeof(pData->FileName), pFileName );
    pData->AlphaLow = Phy_FltClamp01( AlphaLow );
    pData->AlphaMiddle = Phy_FltClamp01( AlphaMiddle );
    pData->AlphaHigh = Phy_FltClamp01( AlphaHigh );

    if ( fgets( Buffer, sizeof(Buffer), pFile ) == NULL )
    {
        fclose( pFile );
        if ( fVerbose )
            Abc_Print( 1, "Physical info file is empty: %s\n", pFileName );
        return pData;
    }

    while ( fgets( Buffer, sizeof(Buffer), pFile ) )
    {
        Phy_NodeInfo_t * pInfo;
        char * pNL;
        nLines++;

        pNL = strchr( Buffer, '\n' );
        if ( pNL )
            *pNL = '\0';
        pNL = strchr( Buffer, '\r' );
        if ( pNL )
            *pNL = '\0';

        if ( Phy_LineIsEmpty(Buffer) )
            continue;

        pInfo = Phy_NodeInfoParse( Buffer );
        if ( pInfo == NULL )
        {
            if ( fVerbose )
                Abc_Print( 1, "Skipping malformed line %d in %s\n", nLines + 1, pFileName );
            continue;
        }
        Vec_PtrPush( pData->vNodes, pInfo );
    }
    fclose( pFile );

    if ( fVerbose )
        Abc_Print( 1, "Loaded %d physical records from %s\n", Vec_PtrSize(pData->vNodes), pFileName );

    Phy_DataRecomputePotential( pData, pData->AlphaLow, pData->AlphaMiddle, pData->AlphaHigh, fVerbose );
    return pData;
}

int Phy_DataWriteCsv( Phy_Data_t * pData, const char * pFileName, int fVerbose )
{
    Phy_NodeInfo_t * pInfo;
    FILE * pFile;
    int i;

    if ( pData == NULL || pData->vNodes == NULL )
        return 0;

    pFile = fopen( pFileName, "w" );
    if ( pFile == NULL )
    {
        Abc_Print( -1, "Cannot write physical info file: %s\n", pFileName );
        return 0;
    }

    fprintf( pFile, "objId,type,node_name,fanin_count,fanin0_name,fanin1_name,fanout,arrival,required,slack,level,area,gate_name,criticality,opt_potential,struct_raw,struct_potential,slack_potential,opt_potential_low,opt_potential_middle,opt_potential_high,fanin0_objId,fanin1_objId\n" );
    Vec_PtrForEachEntry( Phy_NodeInfo_t *, pData->vNodes, pInfo, i )
    {
        fprintf( pFile, "%d,%s,%s,%d,%s,%s,%d,%.6f,%.6f,%.6f,%d,%.2f,%s,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%d,%d\n",
            pInfo->ObjId, pInfo->Type, pInfo->NodeName, pInfo->FaninCount, pInfo->Fanin0, pInfo->Fanin1,
            pInfo->Fanout, pInfo->Arrival, pInfo->Required, pInfo->Slack, pInfo->Level, pInfo->Area,
            pInfo->GateName, pInfo->Criticality, pInfo->OptPotential, pInfo->StructPotentialRaw,
            pInfo->StructPotential, pInfo->SlackPotential,
            pInfo->OptPotentialLow, pInfo->OptPotentialMiddle, pInfo->OptPotentialHigh,
            pInfo->Fanin0ObjId, pInfo->Fanin1ObjId );
    }
    fclose( pFile );

    if ( fVerbose )
        Abc_Print( 1, "Wrote %d records with rebuilt potentials to %s\n", Vec_PtrSize(pData->vNodes), pFileName );
    return 1;
}

void Phy_DataPrintStats( Phy_Data_t * pData )
{
    Phy_NodeInfo_t * pInfo;
    int i;
    int nAnd = 0, nNand = 0, nInv = 0, nOther = 0;

    if ( pData == NULL )
    {
        Abc_Print( -1, "Physical data is NULL.\n" );
        return;
    }

    Vec_PtrForEachEntry( Phy_NodeInfo_t *, pData->vNodes, pInfo, i )
    {
        if ( !strncmp( pInfo->GateName, "AND", 3 ) )
            nAnd++;
        else if ( !strncmp( pInfo->GateName, "NAND", 4 ) )
            nNand++;
        else if ( !strncmp( pInfo->GateName, "INV", 3 ) )
            nInv++;
        else
            nOther++;
    }

    Abc_Print( 1, "Physical records : %d\n", Vec_PtrSize(pData->vNodes) );
    Abc_Print( 1, "Gate summary     : NAND=%d AND=%d INV=%d OTHER=%d\n", nNand, nAnd, nInv, nOther );
    Abc_Print( 1, "Alpha (L/M/H)    : %.3f / %.3f / %.3f\n", pData->AlphaLow, pData->AlphaMiddle, pData->AlphaHigh );
}

static int Phy_NodeCmpOptPotential( const void * pA, const void * pB )
{
    const Phy_NodeInfo_t * pN1 = *(const Phy_NodeInfo_t * const *)pA;
    const Phy_NodeInfo_t * pN2 = *(const Phy_NodeInfo_t * const *)pB;
    if ( pN1->OptPotential < pN2->OptPotential )
        return s_PhySortDescending ? 1 : -1;
    if ( pN1->OptPotential > pN2->OptPotential )
        return s_PhySortDescending ? -1 : 1;
    return (pN1->ObjId > pN2->ObjId) - (pN1->ObjId < pN2->ObjId);
}

static int Phy_NodeCmpOptPotentialLow( const void * pA, const void * pB )
{
    const Phy_NodeInfo_t * pN1 = *(const Phy_NodeInfo_t * const *)pA;
    const Phy_NodeInfo_t * pN2 = *(const Phy_NodeInfo_t * const *)pB;
    if ( pN1->OptPotentialLow < pN2->OptPotentialLow )
        return s_PhySortDescending ? 1 : -1;
    if ( pN1->OptPotentialLow > pN2->OptPotentialLow )
        return s_PhySortDescending ? -1 : 1;
    return (pN1->ObjId > pN2->ObjId) - (pN1->ObjId < pN2->ObjId);
}

static int Phy_NodeCmpOptPotentialMiddle( const void * pA, const void * pB )
{
    const Phy_NodeInfo_t * pN1 = *(const Phy_NodeInfo_t * const *)pA;
    const Phy_NodeInfo_t * pN2 = *(const Phy_NodeInfo_t * const *)pB;
    if ( pN1->OptPotentialMiddle < pN2->OptPotentialMiddle )
        return s_PhySortDescending ? 1 : -1;
    if ( pN1->OptPotentialMiddle > pN2->OptPotentialMiddle )
        return s_PhySortDescending ? -1 : 1;
    return (pN1->ObjId > pN2->ObjId) - (pN1->ObjId < pN2->ObjId);
}

static int Phy_NodeCmpOptPotentialHigh( const void * pA, const void * pB )
{
    const Phy_NodeInfo_t * pN1 = *(const Phy_NodeInfo_t * const *)pA;
    const Phy_NodeInfo_t * pN2 = *(const Phy_NodeInfo_t * const *)pB;
    if ( pN1->OptPotentialHigh < pN2->OptPotentialHigh )
        return s_PhySortDescending ? 1 : -1;
    if ( pN1->OptPotentialHigh > pN2->OptPotentialHigh )
        return s_PhySortDescending ? -1 : 1;
    return (pN1->ObjId > pN2->ObjId) - (pN1->ObjId < pN2->ObjId);
}

static int Phy_NodeCmpCriticality( const void * pA, const void * pB )
{
    const Phy_NodeInfo_t * pN1 = *(const Phy_NodeInfo_t * const *)pA;
    const Phy_NodeInfo_t * pN2 = *(const Phy_NodeInfo_t * const *)pB;
    if ( pN1->Criticality < pN2->Criticality )
        return s_PhySortDescending ? 1 : -1;
    if ( pN1->Criticality > pN2->Criticality )
        return s_PhySortDescending ? -1 : 1;
    return (pN1->ObjId > pN2->ObjId) - (pN1->ObjId < pN2->ObjId);
}

void Phy_DataSortByOptPotential( Phy_Data_t * pData, int fDescending )
{
    if ( pData == NULL || pData->vNodes == NULL || Vec_PtrSize(pData->vNodes) < 2 )
        return;
    s_PhySortDescending = fDescending ? 1 : 0;
    qsort( pData->vNodes->pArray, (size_t)Vec_PtrSize(pData->vNodes), sizeof(void *), Phy_NodeCmpOptPotential );
}

void Phy_DataSortByOptPotentialLow( Phy_Data_t * pData, int fDescending )
{
    if ( pData == NULL || pData->vNodes == NULL || Vec_PtrSize(pData->vNodes) < 2 )
        return;
    s_PhySortDescending = fDescending ? 1 : 0;
    qsort( pData->vNodes->pArray, (size_t)Vec_PtrSize(pData->vNodes), sizeof(void *), Phy_NodeCmpOptPotentialLow );
}

void Phy_DataSortByOptPotentialMiddle( Phy_Data_t * pData, int fDescending )
{
    if ( pData == NULL || pData->vNodes == NULL || Vec_PtrSize(pData->vNodes) < 2 )
        return;
    s_PhySortDescending = fDescending ? 1 : 0;
    qsort( pData->vNodes->pArray, (size_t)Vec_PtrSize(pData->vNodes), sizeof(void *), Phy_NodeCmpOptPotentialMiddle );
}

void Phy_DataSortByOptPotentialHigh( Phy_Data_t * pData, int fDescending )
{
    if ( pData == NULL || pData->vNodes == NULL || Vec_PtrSize(pData->vNodes) < 2 )
        return;
    s_PhySortDescending = fDescending ? 1 : 0;
    qsort( pData->vNodes->pArray, (size_t)Vec_PtrSize(pData->vNodes), sizeof(void *), Phy_NodeCmpOptPotentialHigh );
}

void Phy_DataSortByCriticality( Phy_Data_t * pData, int fDescending )
{
    if ( pData == NULL || pData->vNodes == NULL || Vec_PtrSize(pData->vNodes) < 2 )
        return;
    s_PhySortDescending = fDescending ? 1 : 0;
    qsort( pData->vNodes->pArray, (size_t)Vec_PtrSize(pData->vNodes), sizeof(void *), Phy_NodeCmpCriticality );
}

void Phy_DataPrintTop( Phy_Data_t * pData, int nTop )
{
    Phy_NodeInfo_t * pInfo;
    int i, nSize;
    if ( pData == NULL || pData->vNodes == NULL )
        return;
    nSize = Vec_PtrSize( pData->vNodes );
    if ( nTop <= 0 || nTop > nSize )
        nTop = nSize;
    Abc_Print( 1, "Top %d entries:\n", nTop );
    Abc_Print( 1, "  rank objId node gate crit opt_low opt_mid opt_high struct_pot slack_pot slack\n" );
    for ( i = 0; i < nTop; i++ )
    {
        pInfo = (Phy_NodeInfo_t *)Vec_PtrEntry( pData->vNodes, i );
        Abc_Print( 1, "  %4d %5d %-12s %-10s %6.3f %7.4f %7.4f %8.4f %10.6f %9.6f %9.6f\n",
            i + 1, pInfo->ObjId, pInfo->NodeName, pInfo->GateName,
            pInfo->Criticality, pInfo->OptPotentialLow, pInfo->OptPotentialMiddle, pInfo->OptPotentialHigh,
            pInfo->StructPotential, pInfo->SlackPotential, pInfo->Slack );
    }
}

void Phy_DataFree( Phy_Data_t * pData )
{
    Phy_NodeInfo_t * pInfo;
    int i;
    if ( pData == NULL )
        return;
    Vec_PtrForEachEntry( Phy_NodeInfo_t *, pData->vNodes, pInfo, i )
        ABC_FREE( pInfo );
    Vec_PtrFree( pData->vNodes );
    ABC_FREE( pData );
}

ABC_NAMESPACE_IMPL_END
