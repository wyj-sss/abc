/**CFile****************************************************************

  FileName    [mapperExtract.c]

  SystemName  [ABC: Logic synthesis and verification system.]

  PackageName [Mapper package.]

  Synopsis    [Extract timing and structure info from mapped networks.]

  Author      [Your Name]

  Affiliation [Your Affiliation]

  Date        [Date]

***********************************************************************/

#include "mapperInt.h"

ABC_NAMESPACE_IMPL_START

////////////////////////////////////////////////////////////////////////
///                        PARAMETERS                                ///
////////////////////////////////////////////////////////////////////////

typedef struct MapperExtractPar_t_
{
    char * pFileName;      // output CSV file
    int    fCheck;         // enable internal consistency checks
    int    nSample;        // print first N sampled lines to stdout
    int    fNodesOnly;     // only internal nodes (skip CI/CO)
    int    fVerbose;       // verbose output
} MapperExtractPar_t;

static void MapperExtractSetDefaultPars( MapperExtractPar_t * Pars )
{
    memset( Pars, 0, sizeof(*Pars) );
    Pars->pFileName  = NULL;
    Pars->fCheck     = 0;
    Pars->nSample    = 0;
    Pars->fNodesOnly = 1;
    Pars->fVerbose   = 0;
}

static int MapperExtractParseArgs( int argc, char ** argv, MapperExtractPar_t * Pars )
{
    int c;
    Extra_UtilGetoptReset();
    while ( (c = Extra_UtilGetopt( argc, argv, "o:cs:nvh" )) != EOF )
    {
        switch ( c )
        {
        case 'o':
            Pars->pFileName = (char *)globalUtilOptarg;
            break;
        case 'c':
            Pars->fCheck = 1;
            break;
        case 's':
            Pars->nSample = atoi(globalUtilOptarg);
            if ( Pars->nSample < 0 ) Pars->nSample = 0;
            break;
        case 'n':
            Pars->fNodesOnly = 0;
            break;
        case 'v':
            Pars->fVerbose = 1;
            break;
        case 'h':
        default:
            return 0;
        }
    }
    return 1;
}

static void MapperExtractPrintUsage( void )
{
    Abc_Print( 1, "usage: mapper_extract -o <file.csv> [-c] [-s <num>] [-n] [-v]\n" );
    Abc_Print( 1, "  -o <file> : output CSV file (required)\n" );
    Abc_Print( 1, "  -c        : enable self-checks (finite timing, slack=req-arr)\n" );
    Abc_Print( 1, "  -s <num>  : print first <num> extracted lines to stdout\n" );
    Abc_Print( 1, "  -n        : include CIs/COs (default: nodes only)\n" );
    Abc_Print( 1, "  -v        : verbose output\n" );
    Abc_Print( 1, "\n" );
}

////////////////////////////////////////////////////////////////////////
///                        HELPER FUNCTIONS                          ///
////////////////////////////////////////////////////////////////////////

static inline int MapperExtractIsFinite( float x )
{
#ifdef _MSC_VER
    return _finite(x);
#else
    return isfinite(x);
#endif
}

/**Function*************************************************************

  Synopsis    [Compute criticality: 1 - (slack / max_slack)]

  Description [Returns a value between 0 and 1 indicating how close
  the node is to the critical path. 1 = critical, 0 = not critical.]

***********************************************************************/
static float MapperExtractComputeCriticality( float slack, float maxSlack )
{
    if ( maxSlack <= 0.0f )
        return 0.0f;
    return 1.0f - (slack / maxSlack);
}

/**Function*************************************************************

  Synopsis    [Find maximum slack value in the network.]

  Description [Scans all nodes to find the maximum slack (most slack).]

***********************************************************************/
// ✅ 【改进】Find maximum slack value using computed arrivals and required
static float MapperExtractFindMaxSlack( double * arrivals, double * required, Abc_Ntk_t * pNtk, int fNodesOnly )
{
    Abc_Obj_t * pObj;
    int i, id;
    float maxSlack = 0.0f;
    double arr, req, slk;

    if ( fNodesOnly )
    {
        Abc_NtkForEachNode( pNtk, pObj, i )
        {
            id = Abc_ObjId(pObj);
            arr = arrivals[id];
            req = required[id];
            slk = req - arr;
            if ( slk > maxSlack )
                maxSlack = (float)slk;
        }
    }
    else
    {
        Abc_NtkForEachObj( pNtk, pObj, i )
        {
            if ( !Abc_ObjIsNode(pObj) )
                continue;
            id = Abc_ObjId(pObj);
            arr = arrivals[id];
            req = required[id];
            slk = req - arr;
            if ( slk > maxSlack )
                maxSlack = (float)slk;
        }
    }

    return maxSlack;
}

/**Function*************************************************************

  Synopsis    [Get fanin name - use PI name if available, else generate from objId]

  Description []

***********************************************************************/
static const char * MapperExtractGetFaninName( Abc_Obj_t * pFanin, char * pBuffer )
{
    if ( pFanin == NULL )
        return "";
    
    // 如果是 PI，用输入名
    if ( Abc_ObjIsCi(pFanin) )
    {
        const char * pName = Abc_ObjName( pFanin );
        if ( pName != NULL && strlen(pName) > 0 )
            return pName;
    }
    
    // 如果是内部节点，生成 n<objId> 的格式
    if ( Abc_ObjIsNode(pFanin) )
    {
        int objId = Abc_ObjId( pFanin );
        sprintf( pBuffer, "n%d", objId );
        return pBuffer;  // ✅ 返回传入的 pBuffer
    }
    
    // 其他情况返回空
    return "";
}

/**Function*************************************************************

  Synopsis    [Get gate name from cell data.]

  Description [Returns the name of the cell this node is mapped to,
  or "UNKNOWN" if not available.]

***********************************************************************/
static const char * MapperExtractGetGateName( Abc_Obj_t * pObj )
{
    Mio_Gate_t * pGate;

    if ( !Abc_ObjIsNode(pObj) )
        return "N/A";

    pGate = (Mio_Gate_t *)pObj->pData;
    if ( pGate == NULL )
        return "UNMAPPED";

    return Mio_GateReadName( pGate );
}

// ✅ 【新增】Compare function for qsort
static int MapperExtractCompareByLevel( const void * p1, const void * p2 )
{
    Abc_Obj_t * pObj1 = *(Abc_Obj_t **)p1;
    Abc_Obj_t * pObj2 = *(Abc_Obj_t **)p2;
    int lev1 = Abc_ObjLevel(pObj1);
    int lev2 = Abc_ObjLevel(pObj2);
    return lev1 - lev2;
}

/**Function*************************************************************

  Synopsis    [Compute arrival times for all nodes (forward pass)]

  Description [Recursively computes arrival time for each node as:
  arrival[node] = max(arrival[fanin0], arrival[fanin1]) + gate_delay]

***********************************************************************/
static void MapperExtractComputeArrivals( Abc_Ntk_t * pNtk, double * arrivals, int nObjsAlloc, Abc_Obj_t ** pNodes, int nNodes )
{
    Abc_Obj_t * pObj, * pFan0, * pFan1;
    Mio_Gate_t * pGate;
    double gateDelay, arr0, arr1, arr;
    int i, id, fan0Id, fan1Id, nFanins;

    // Initialize all arrivals to 0 (PIs have arrival 0)
    for ( i = 0; i < nObjsAlloc; i++ )
        arrivals[i] = 0.0;

    // Forward pass: compute arrival for each node sorted by level
    for ( i = 0; i < nNodes; i++ )
    {
        pObj = pNodes[i];
        id = Abc_ObjId( pObj );

        if ( !Abc_ObjIsNode(pObj) )
            continue;

        nFanins = Abc_ObjFaninNum( pObj );

        // Get fanins
        pFan0 = (nFanins > 0) ? Abc_ObjFanin0(pObj) : NULL;
        pFan1 = (nFanins > 1) ? Abc_ObjFanin1(pObj) : NULL;

        arr = 0.0;
        if ( pFan0 )
        {
            fan0Id = Abc_ObjId(pFan0);
            arr0 = arrivals[fan0Id];
            arr = arr0;
        }

        if ( pFan1 )
        {
            fan1Id = Abc_ObjId(pFan1);
            arr1 = arrivals[fan1Id];
            arr = (arr1 > arr) ? arr1 : arr;
        }

        // Get gate delay
        pGate = (Mio_Gate_t *)pObj->pData;
        if ( pGate != NULL )
        {
            gateDelay = Mio_GateReadDelayMax( pGate );
            arr += gateDelay;
        }

        arrivals[id] = arr;
    }
}
// ✅ 【新增】Compute required times for all nodes (backward pass)
static void MapperExtractComputeRequired( Abc_Ntk_t * pNtk, double * arrivals, double * required, int nObjsAlloc, Abc_Obj_t ** pNodes, int nNodes )
{
    Abc_Obj_t * pObj, * pFan0, * pFan1, * pCo;
    Mio_Gate_t * pGate;
    double gateDelay, req0, req1, req;
        int i, id, fan0Id, fan1Id, nFanins;
    
    // Initialize all required to very large value (infinity)
    for ( i = 0; i < nObjsAlloc; i++ )
        required[i] = 1e9;

    // ✅ 【第一步】Set required for all PO nodes = their arrival times
    // (assumes no timing constraint, so deadline = arrival)
    Abc_NtkForEachCo( pNtk, pCo, i )
    {
        Abc_Obj_t * pFanin = Abc_ObjFanin0(pCo);
        if ( Abc_ObjIsNode(pFanin) )
        {
            int coId = Abc_ObjId(pFanin);
            // Set PO required = its arrival (no timing slack available)
            required[coId] = arrivals[coId];
        }
    }

    // ✅ 【第二步】Backward pass: propagate required from PO to PI
    // Process nodes in reverse level order (from high level to low level)
    for ( i = nNodes - 1; i >= 0; i-- )
    {
        pObj = pNodes[i];
        id = Abc_ObjId( pObj );

        if ( !Abc_ObjIsNode(pObj) )
            continue;

        nFanins = Abc_ObjFaninNum( pObj );

        // Get this node's required time
        req = required[id];
        if ( req >= 1e9 )
            continue;  // Not yet constrained

        // Get gate delay
        pGate = (Mio_Gate_t *)pObj->pData;
        gateDelay = 0.0;
        if ( pGate != NULL )
            gateDelay = Mio_GateReadDelayMax( pGate );

        // Propagate required to fanins
        pFan0 = (nFanins > 0) ? Abc_ObjFanin0(pObj) : NULL;
        pFan1 = (nFanins > 1) ? Abc_ObjFanin1(pObj) : NULL;

        if ( pFan0 )
        {
            fan0Id = Abc_ObjId(pFan0);
            req0 = req - gateDelay;
            if ( req0 < required[fan0Id] )
                required[fan0Id] = req0;
        }

        if ( pFan1 )
        {
            fan1Id = Abc_ObjId(pFan1);
            req1 = req - gateDelay;
            if ( req1 < required[fan1Id] )
                required[fan1Id] = req1;
        }
    }

    // ✅ 【第三步】Clean up: set required for unconstrained nodes to their arrival
    for ( i = 0; i < nNodes; i++ )
    {
        pObj = pNodes[i];
        id = Abc_ObjId( pObj );
        
        if ( !Abc_ObjIsNode(pObj) )
            continue;

        if ( required[id] >= 1e9 )
            required[id] = arrivals[id];  // No constraint, so req = arr
    }
}
/**Function*************************************************************

  Synopsis    [Get node name from ABC object.]

  Description []

***********************************************************************/
static const char * MapperExtractGetNodeName( Abc_Obj_t * pObj )
{
    if ( pObj == NULL )
        return "";
    
    // 直接用 Abc_ObjName，它返回的是指针不会被覆盖
    const char * pName = Abc_ObjName( pObj );
    if ( pName != NULL && strlen(pName) > 0 )
        return pName;
    
    // 其他情况返回空
    return "";
}
/**Function*************************************************************

  Synopsis    [Extract timing and structure info and write to CSV.]

***********************************************************************/
static int MapperExtractWriteCsv( Abc_Ntk_t * pNtk, MapperExtractPar_t * Pars )
{
    FILE * fp;
    Abc_Obj_t * pObj;
    Abc_Obj_t ** pNodes;
    int i, nLines = 0, nBad = 0, nPrinted = 0, nNodes = 0;
    float arr, req, slk, criticality, optPotential;
    float maxSlack;
    double arrivalVal;
    int level, id, nFanins, fo, f0, f1, faninCount;
    const char * pType, *pGateName;
    Mio_Gate_t * pGate;
    double * arrivals;  // ✅ 【新增】arrival 数组
    double * required;
    int nObjsAlloc;

    // ✅ 【新增】计算网络层级
    Abc_NtkLevel( pNtk );
    
    if ( Pars->pFileName == NULL )
    {
        Abc_Print( -1, "mapper_extract: output file is not specified.\n" );
        return 0;
    }

    fp = fopen( Pars->pFileName, "w" );
    if ( fp == NULL )
    {
        Abc_Print( -1, "mapper_extract: cannot open file \"%s\" for writing.\n", Pars->pFileName );
        return 0;
    }

    if ( Pars->fVerbose )
        Abc_Print( 1, "mapper_extract: extracting to \"%s\"...\n", Pars->pFileName );

    nObjsAlloc = Abc_NtkObjNumMax( pNtk ) + 1;
    arrivals = (double *)ABC_ALLOC( double, nObjsAlloc );
    required = (double *)ABC_ALLOC( double, nObjsAlloc );
    if ( arrivals == NULL || required == NULL )
    {
        Abc_Print( -1, "mapper_extract: memory allocation failed for timing arrays.\n" );
        if ( fp ) fclose( fp );
        ABC_FREE( arrivals );
        ABC_FREE( required );
        return 0;
    }

    // ✅ 【新增】收集所有节点，按 level 排序
    pNodes = (Abc_Obj_t **)ABC_ALLOC( Abc_Obj_t *, Abc_NtkNodeNum(pNtk) + 1 );
    nNodes = 0;
    Abc_NtkForEachNode( pNtk, pObj, i )
    {
        pNodes[nNodes++] = pObj;
    }
    
    // 按 level 排序 (fixed lambda)
    qsort( pNodes, nNodes, sizeof(Abc_Obj_t *), MapperExtractCompareByLevel );

    // ✅ 【新增】计算所有 arrival 值
    MapperExtractComputeArrivals( pNtk, arrivals, nObjsAlloc, pNodes, nNodes );

    // ✅ 【新增】计算所有 required 值
    MapperExtractComputeRequired( pNtk, arrivals, required, nObjsAlloc, pNodes, nNodes );
    // Precompute max slack for criticality calculation
        maxSlack = MapperExtractFindMaxSlack( arrivals, required, pNtk, Pars->fNodesOnly );
    if ( Pars->fVerbose )
        Abc_Print( 1, "mapper_extract: max slack = %.6f\n", maxSlack );

    // CSV Header - Extended with new fields
    fprintf( fp, "objId,type,node_name,fanin_count,fanin0_name,fanin1_name,fanout,arrival,required,slack,level,area,gate_name,criticality,opt_potential,fanin0_objId,fanin1_objId\n" );
    // ✅ 【新增】DEBUG: Node ID Mapping
    if ( Pars->fVerbose )
    {
        Abc_Print( 1, "\n=== DEBUG: Node ID Mapping ===\n" );
        Abc_Print( 1, "Format: objId | Name | Type | Fanin0 | Fanin1 | Gate | pData\n" );

        Abc_NtkForEachNode( pNtk, pObj, i )
        {
            int id = Abc_ObjId( pObj );
            const char * name = Abc_ObjName( pObj ) ? Abc_ObjName( pObj ) : "(null)";
            int fan0 = Abc_ObjFanin0(pObj) ? Abc_ObjId(Abc_ObjFanin0(pObj)) : -1;
            int fan1 = Abc_ObjFanin1(pObj) ? Abc_ObjId(Abc_ObjFanin1(pObj)) : -1;
            
            Mio_Gate_t * pGate = (Mio_Gate_t *)pObj->pData;
            const char * gateName = pGate ? Mio_GateReadName(pGate) : "NULL";
            
            Abc_Print( 1, "%3d | %-10s | NODE | %3d | %3d | %s | %p\n", 
                       id, name, fan0, fan1, gateName, pObj->pData );
        }
        Abc_Print( 1, "==============================\n\n" );
    }

    // ✅ 【改进】Extract data - 使用计算好的 arrival
    if ( Pars->fNodesOnly )
    {
        // Extract only internal logic nodes (mapped gates)
        Abc_NtkForEachNode( pNtk, pObj, i )
        {
            id         = Abc_ObjId( pObj );
            nFanins    = Abc_ObjFaninNum( pObj );
            faninCount = nFanins;
            fo         = Abc_ObjFanoutNum( pObj );
            f0         = (nFanins > 0) ? Abc_ObjId( Abc_ObjFanin0(pObj) ) : -1;
            f1         = (nFanins > 1) ? Abc_ObjId( Abc_ObjFanin1(pObj) ) : -1;

            // ✅ 【改进】Get arrival from computed array
            arrivalVal = arrivals[id];
            arr = (float)arrivalVal;

            // ✅ 【改进】Get required from computed array
            req = (float)required[id];
            slk = req - arr;

            // Get level
            level = Abc_ObjLevel( pObj );

            // Area: normalized to 1.0 per gate for K=2 mapping
            float area = 1.0f;

                        // Get node name
            const char * nodeName = MapperExtractGetNodeName( pObj );
            
            // Gate name
            pGateName = MapperExtractGetGateName( pObj );
            pGate = (Mio_Gate_t *)pObj->pData;
            
            // Criticality: 1 - (slack / max_slack)
            criticality = MapperExtractComputeCriticality( slk, maxSlack );

            // Optimization potential: area × slack
            optPotential = area * slk;

            // Perform checks if enabled
            if ( Pars->fCheck )
            {
                if ( !MapperExtractIsFinite(arr) || !MapperExtractIsFinite(req) || !MapperExtractIsFinite(slk) )
                {
                    Abc_Print( -1, "mapper_extract: non-finite timing at obj %d (arr=%f req=%f slk=%f)\n", 
                               id, arr, req, slk );
                    nBad++;
                }
                // Check slack identity
                if ( fabsf( slk - (req - arr) ) > 1e-4f )
                {
                    Abc_Print( -1, "mapper_extract: slack mismatch at obj %d (slack=%f != req-arr=%f)\n", 
                               id, slk, req - arr );
                    nBad++;
                }
                // Warn if fanin > 2 (K=2 constraint)
                if ( nFanins > 2 )
                {
                    Abc_Print( -1, "mapper_extract: warning obj %d has %d fanins (expected K=2)\n", 
                               id, nFanins );
                }
            }

                        // Get fanin names
            char buf0[32], buf1[32];
            Abc_Obj_t * pFan0Obj = (nFanins > 0) ? Abc_ObjFanin0(pObj) : NULL;
            Abc_Obj_t * pFan1Obj = (nFanins > 1) ? Abc_ObjFanin1(pObj) : NULL;
            const char * fan0Name = MapperExtractGetFaninName( pFan0Obj, buf0 );
            const char * fan1Name = MapperExtractGetFaninName( pFan1Obj, buf1 );
            
            // Write to CSV
            fprintf( fp, "%d,%s,%s,%d,%s,%s,%d,%.6f,%.6f,%.6f,%d,%.2f,%s,%.6f,%.6f,%d,%d\n",
            id, "NODE", nodeName, faninCount, fan0Name, fan1Name, fo, arr, req, slk, level, area, pGateName, criticality, optPotential, f0, f1 );
            nLines++;

            // Print samples to stdout
            if ( Pars->nSample > 0 && nPrinted < Pars->nSample )
            {
                Abc_Print( 1, "[%d] id=%d f0=%d f1=%d fo=%d arr=%.6f req=%.6f slk=%.6f crit=%.6f opt_pot=%.6f gate=%s\n",
                           nPrinted, id, f0, f1, fo, arr, req, slk, criticality, optPotential, pGateName );
                nPrinted++;
            }
        }
    }
    else
    {
        // Extract all objects (CIs, COs, and nodes)
        Abc_NtkForEachObj( pNtk, pObj, i )
        {
            id         = Abc_ObjId( pObj );
            nFanins    = Abc_ObjFaninNum( pObj );
            faninCount = nFanins;
            fo         = Abc_ObjFanoutNum( pObj );
            f0         = (nFanins > 0) ? Abc_ObjId( Abc_ObjFanin0(pObj) ) : -1;
            f1         = (nFanins > 1) ? Abc_ObjId( Abc_ObjFanin1(pObj) ) : -1;

            // Determine object type
            if ( Abc_ObjIsCi(pObj) )
                pType = "CI";
            else if ( Abc_ObjIsCo(pObj) )
                pType = "CO";
            else if ( Abc_ObjIsNode(pObj) )
                pType = "NODE";
            else
                pType = "OBJ";

            // ✅ 【改进】Get arrival from computed array
            if ( Abc_ObjIsNode(pObj) )
                arrivalVal = arrivals[id];
            else
                arrivalVal = 0.0;
            arr = (float)arrivalVal;

            // ✅ 【改进】Get required from computed array
            if ( Abc_ObjIsNode(pObj) )
                req = (float)required[id];
            else
                req = 0.0f;
            slk = req - arr;

#ifdef Abc_ObjLevel
            level = Abc_ObjLevel( pObj );
#else
            level = -1;
#endif

            // Area only for nodes
            float area = Abc_ObjIsNode(pObj) ? 1.0f : 0.0f;

                        // Get node name
            const char * nodeName = Abc_ObjIsNode(pObj) ? MapperExtractGetNodeName( pObj ) : "";
            
            // Gate name
            pGateName = Abc_ObjIsNode(pObj) ? MapperExtractGetGateName( pObj ) : "N/A";

            // Criticality (only meaningful for nodes)
            criticality = Abc_ObjIsNode(pObj) ? MapperExtractComputeCriticality( slk, maxSlack ) : 0.0f;

            // Optimization potential
            optPotential = area * slk;

            // Perform checks
            if ( Pars->fCheck )
            {
                if ( !MapperExtractIsFinite(arr) || !MapperExtractIsFinite(req) || !MapperExtractIsFinite(slk) )
                    nBad++;
            }

                        // Get fanin names
            char buf0[32], buf1[32];
            Abc_Obj_t * pFan0Obj = (nFanins > 0) ? Abc_ObjFanin0(pObj) : NULL;
            Abc_Obj_t * pFan1Obj = (nFanins > 1) ? Abc_ObjFanin1(pObj) : NULL;
            const char * fan0Name = MapperExtractGetFaninName( pFan0Obj, buf0 );
            const char * fan1Name = MapperExtractGetFaninName( pFan1Obj, buf1 );
            
            // Write to CSV
            fprintf( fp, "%d,%s,%s,%d,%s,%s,%d,%.6f,%.6f,%.6f,%d,%.2f,%s,%.6f,%.6f,%d,%d\n",
            id, pType, nodeName, faninCount, fan0Name, fan1Name, fo, arr, req, slk, level, area, pGateName, criticality, optPotential, f0, f1 );
            nLines++;
        }
    }

    fclose( fp );

    // ✅ 【新增】释放内存
    ABC_FREE( arrivals );
    ABC_FREE( required );
    ABC_FREE( pNodes );

    Abc_Print( 1, "mapper_extract: wrote %d lines to \"%s\".\n", nLines, Pars->pFileName );
    if ( Pars->fCheck && nBad > 0 )
        Abc_Print( 1, "mapper_extract: %d bad entries detected.\n", nBad );

    // Return failure if checks found bad entries
    if ( Pars->fCheck && nBad > 0 )
        return 0;

    return 1;
}

/**Function*************************************************************

  Synopsis    [Get fanin name - use PI name if available, else use objId]

  Description [Returns the name of fanin node (input name or node name)]

***********************************************************************/

////////////////////////////////////////////////////////////////////////
///                     EXPORTED FUNCTIONS                           ///
////////////////////////////////////////////////////////////////////////

int MapperExtractRun( Abc_Ntk_t * pNtk, const char * pFileName, int fVerbose )
{
    MapperExtractPar_t Pars;
    
    if ( pNtk == NULL )
        return 0;
    
    if ( !Abc_NtkIsMappedLogic(pNtk) )
    {
        Abc_Print( -1, "mapper_extract: network is not mapped logic.\n" );
        return 0;
    }

    MapperExtractSetDefaultPars( &Pars );
    Pars.pFileName = (char *)pFileName;
    Pars.fVerbose  = fVerbose;
    Pars.fCheck    = 1;

    return MapperExtractWriteCsv( pNtk, &Pars );
}

////////////////////////////////////////////////////////////////////////
///                        COMMAND                                   ///
////////////////////////////////////////////////////////////////////////

int Mapper_CommandExtract( Abc_Frame_t * pAbc, int argc, char ** argv )
{
    MapperExtractPar_t Pars;
    Abc_Ntk_t * pNtk;
    int c;

    MapperExtractSetDefaultPars( &Pars );

    Extra_UtilGetoptReset();
    while ( (c = Extra_UtilGetopt( argc, argv, "o:cs:nvh" )) != EOF )
    {
        switch ( c )
        {
        case 'o':
            Pars.pFileName = (char *)globalUtilOptarg;
            break;
        case 'c':
            Pars.fCheck = 1;
            break;
        case 's':
            Pars.nSample = atoi(globalUtilOptarg);
            if ( Pars.nSample < 0 ) Pars.nSample = 0;
            break;
        case 'n':
            Pars.fNodesOnly = 0;
            break;
        case 'v':
            Pars.fVerbose = 1;
            break;
        case 'h':
            goto usage;
        default:
            goto usage;
        }
    }

    if ( Pars.pFileName == NULL )
    {
        Pars.pFileName = "output.csv";  // ✅ 默认输出到当前目录
    }

    pNtk = Abc_FrameReadNtk( pAbc );
    if ( pNtk == NULL )
    {
        Abc_Print( -1, "mapper_extract: there is no current network.\n" );
        return 1;
    }

    if ( !Abc_NtkIsMappedLogic(pNtk) )
    {
        Abc_Print( -1, "mapper_extract: current network is not mapped. Run 'map' or 'map_oto' first.\n" );
        return 1;
    }

    if ( Pars.fVerbose )
        Abc_Print( 1, "mapper_extract: starting extraction...\n" );

    if ( !MapperExtractWriteCsv( pNtk, &Pars ) )
        return 1;

    if ( Pars.fVerbose )
        Abc_Print( 1, "mapper_extract: done.\n" );

    return 0;

usage:
    MapperExtractPrintUsage();
    return 1;
}

ABC_NAMESPACE_IMPL_END