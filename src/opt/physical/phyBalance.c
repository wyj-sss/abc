#include "opt/physical/phyOpt.h"
#include "opt/physical/phyInfo.h"
#include "bool/kit/kit.h"
#include "map/mio/mio.h"
#include "base/abc/abc.h"
#include "aig/aig/aig.h"

ABC_NAMESPACE_IMPL_START

/* ---- Shared from phyRewrite.c ---- */
extern Phy_GateCostLut_t Phy_GateCostLut[16];
extern int               Phy_fLutInit;
extern float             Phy_BaseArea;
extern float             Phy_BaseDelay;

extern void         Phy_RewriteInitLut( Mio_Library_t * pLib );
extern Aig_Obj_t *  Phy_RewriteDsdToAig( Aig_Man_t * pMan, Kit_DsdNtk_t * pNtk, Aig_Obj_t ** ppLeaves, Vec_Int_t * vMemory );

extern Aig_Obj_t *  Kit_GraphToAig( Aig_Man_t * pMan, Aig_Obj_t ** pFanins, Kit_Graph_t * pGraph );
extern Aig_Man_t *  Abc_NtkToDar( Abc_Ntk_t * pNtk, int fExors, int fRegisters );
extern Abc_Ntk_t *  Abc_NtkFromAigPhase( Aig_Man_t * pMan );

/* ---- Path flags ---- */
#define PHY_BALANCE_PATH_NONE  0
#define PHY_BALANCE_PATH_ISOP  1
#define PHY_BALANCE_PATH_DSD   2
#define PHY_BALANCE_PATH_COF   3

typedef struct
{
    int   bestPath;
    int   bestDepth;       /* tree height (logic levels) */
    int   bestCompl;
    int   bestCofVar;
} Phy_BalanceCand_t;

/* ---- Tree-height scoring (delay = logic levels, not sum of delays) ---- */

static int Phy_BalanceGraphDepth( Kit_Graph_t * pGraph )
{
    int * depth;
    int i, maxDepth = 0;
    if ( pGraph == NULL ) return 999;
    depth = (int *)alloca( pGraph->nSize * sizeof(int) );
    for ( i = 0; i < pGraph->nLeaves; i++ )
        depth[i] = 0;
    for ( i = pGraph->nLeaves; i < pGraph->nSize; i++ )
    {
        Kit_Node_t * pNode = pGraph->pNodes + i;
        int d0 = depth[ pNode->eEdge0.Node ];
        int d1 = depth[ pNode->eEdge1.Node ];
        depth[i] = 1 + ( d0 > d1 ? d0 : d1 );
        if ( depth[i] > maxDepth ) maxDepth = depth[i];
    }
    return maxDepth;
}

static int Phy_BalanceDsdDepth( Kit_DsdNtk_t * pNtk )
{
    int * depth;
    int i, f, maxDepth = 0;
    if ( pNtk == NULL ) return 999;
    depth = (int *)alloca( pNtk->nNodes * sizeof(int) );
    for ( i = 0; i < pNtk->nVars; i++ )
        depth[i] = 0;
    for ( i = pNtk->nVars; i < pNtk->nNodes; i++ )
    {
        Kit_DsdObj_t * pObj = pNtk->pNodes[i];
        int maxd = 0;
        for ( f = 0; f < (int)pObj->nFans; f++ )
        {
            int fan = pObj->pFans[f];
            if ( depth[fan] > maxd ) maxd = depth[fan];
        }
        depth[i] = maxd + 1;
    }
    return depth[ pNtk->Root ];
}

/* ---- Three-path evaluation (depth-driven, not sum-of-delays) ---- */
static int Phy_BalanceEvaluate(
    unsigned *          pTruth,
    int                 nLeaves,
    int                 mffcDepth,      /* current MFFC internal depth (logic levels) */
    Phy_BalanceCand_t * pCand,
    Vec_Int_t *         vMemory )
{
    int bestDepth = 999;
    int bestPath  = PHY_BALANCE_PATH_NONE;
    int bestCompl = 0;
    int bestCofVar = -1;
    int nWords    = Kit_TruthWordNum( nLeaves );
    unsigned * pCof0 = (unsigned *)alloca( nWords * sizeof(unsigned) );
    unsigned * pCof1 = (unsigned *)alloca( nWords * sizeof(unsigned) );

    /* ---- Path 1: ISOP + factoring (minimize depth) ---- */
    {
        int RetValue = Kit_TruthIsop( pTruth, nLeaves, vMemory, 1 );
        if ( RetValue != -1 )
        {
            Kit_Graph_t * pGraph = Kit_SopFactor( vMemory, RetValue, nLeaves, vMemory );
            if ( pGraph != NULL )
            {
                int d = Phy_BalanceGraphDepth( pGraph );
                if ( d < bestDepth )
                {
                    bestDepth = d;
                    bestPath  = PHY_BALANCE_PATH_ISOP;
                    bestCompl = RetValue;
                }
                Kit_GraphFree( pGraph );
            }
        }
    }

    /* ---- Path 2: DSD decomposition (minimize depth) ---- */
    {
        Kit_DsdNtk_t * pNtk = Kit_DsdDecompose( pTruth, nLeaves );
        if ( pNtk != NULL )
        {
            Kit_DsdNtk_t * pExp = Kit_DsdExpand( pNtk );
            Kit_DsdNtkFree( pNtk );
            if ( pExp != NULL )
            {
                int d = Phy_BalanceDsdDepth( pExp );
                if ( d < bestDepth )
                {
                    bestDepth = d;
                    bestPath  = PHY_BALANCE_PATH_DSD;
                    bestCompl = 0;
                }
                Kit_DsdNtkFree( pExp );
            }
        }
    }

    /* ---- Path 3: Cofactoring search (minimize depth) ---- */
    {
        int v;
        for ( v = 0; v < nLeaves; v++ )
        {
            Kit_TruthCofactor0New( pCof0, pTruth, nLeaves, v );
            Kit_TruthCofactor1New( pCof1, pTruth, nLeaves, v );
            if ( ( Kit_TruthIsConst0( pCof0, nLeaves ) || Kit_TruthIsConst1( pCof0, nLeaves ) ) &&
                 ( Kit_TruthIsConst0( pCof1, nLeaves ) || Kit_TruthIsConst1( pCof1, nLeaves ) ) )
                continue;
            Kit_DsdNtk_t * pNtk0 = Kit_DsdDecompose( pCof0, nLeaves );
            Kit_DsdNtk_t * pNtk1 = Kit_DsdDecompose( pCof1, nLeaves );
            if ( pNtk0 == NULL || pNtk1 == NULL )
            { if ( pNtk0 ) Kit_DsdNtkFree( pNtk0 ); if ( pNtk1 ) Kit_DsdNtkFree( pNtk1 ); continue; }
            Kit_DsdNtk_t * pExp0 = Kit_DsdExpand( pNtk0 );
            Kit_DsdNtk_t * pExp1 = Kit_DsdExpand( pNtk1 );
            Kit_DsdNtkFree( pNtk0 ); Kit_DsdNtkFree( pNtk1 );
            if ( pExp0 == NULL || pExp1 == NULL )
            { if ( pExp0 ) Kit_DsdNtkFree( pExp0 ); if ( pExp1 ) Kit_DsdNtkFree( pExp1 ); continue; }
            int d0 = Phy_BalanceDsdDepth( pExp0 );
            int d1 = Phy_BalanceDsdDepth( pExp1 );
            int d  = 1 + ( d0 > d1 ? d0 : d1 ); /* +1 for the mux */
            Kit_DsdNtkFree( pExp0 ); Kit_DsdNtkFree( pExp1 );
            if ( d < bestDepth )
            {
                bestDepth = d;
                bestPath  = PHY_BALANCE_PATH_COF;
                bestCofVar = v;
            }
        }
    }

    pCand->bestPath   = bestPath;
    pCand->bestDepth  = bestDepth;
    pCand->bestCompl  = bestCompl;
    pCand->bestCofVar = bestCofVar;

    /* Accept only if strictly fewer logic levels than current MFFC */
    return ( bestPath != PHY_BALANCE_PATH_NONE && bestDepth < mffcDepth );
}

/* ---- Build winning candidate ---- */
static Aig_Obj_t * Phy_BalanceBuildCandidate(
    Aig_Man_t *          pAig,
    Aig_Obj_t **         ppFanins,
    unsigned *           pTruth,
    int                  nLeaves,
    Phy_BalanceCand_t *  pCand,
    Vec_Int_t *          vMemory )
{
    switch ( pCand->bestPath )
    {
    case PHY_BALANCE_PATH_ISOP:
        {
            int RetValue = Kit_TruthIsop( pTruth, nLeaves, vMemory, 1 );
            if ( RetValue == -1 ) return NULL;
            Kit_Graph_t * pGraph = Kit_SopFactor( vMemory, RetValue, nLeaves, vMemory );
            if ( pGraph == NULL ) return NULL;
            Aig_Obj_t * pRoot = Kit_GraphToAig( pAig, ppFanins, pGraph );
            Kit_GraphFree( pGraph );
            if ( pRoot != NULL && RetValue )
                pRoot = Aig_Not( pRoot );
            return pRoot;
        }
    case PHY_BALANCE_PATH_DSD:
        {
            Kit_DsdNtk_t * pNtk = Kit_DsdDecompose( pTruth, nLeaves );
            if ( pNtk == NULL ) return NULL;
            Kit_DsdNtk_t * pExp = Kit_DsdExpand( pNtk );
            Kit_DsdNtkFree( pNtk );
            if ( pExp == NULL ) return NULL;
            Aig_Obj_t * pRoot = Phy_RewriteDsdToAig( pAig, pExp, ppFanins, vMemory );
            Kit_DsdNtkFree( pExp );
            return pRoot;
        }
    case PHY_BALANCE_PATH_COF:
        {
            int nWordsCof = Kit_TruthWordNum( nLeaves );
            unsigned * pCof0 = (unsigned *)alloca( nWordsCof * sizeof(unsigned) );
            unsigned * pCof1 = (unsigned *)alloca( nWordsCof * sizeof(unsigned) );
            Kit_TruthCofactor0New( pCof0, pTruth, nLeaves, pCand->bestCofVar );
            Kit_TruthCofactor1New( pCof1, pTruth, nLeaves, pCand->bestCofVar );
            Kit_DsdNtk_t * pNtk0 = Kit_DsdDecompose( pCof0, nLeaves );
            Kit_DsdNtk_t * pNtk1 = Kit_DsdDecompose( pCof1, nLeaves );
            if ( pNtk0 == NULL || pNtk1 == NULL )
            { if ( pNtk0 ) Kit_DsdNtkFree( pNtk0 ); if ( pNtk1 ) Kit_DsdNtkFree( pNtk1 ); return NULL; }
            Kit_DsdNtk_t * pExp0 = Kit_DsdExpand( pNtk0 );
            Kit_DsdNtk_t * pExp1 = Kit_DsdExpand( pNtk1 );
            Kit_DsdNtkFree( pNtk0 ); Kit_DsdNtkFree( pNtk1 );
            if ( pExp0 == NULL || pExp1 == NULL )
            { if ( pExp0 ) Kit_DsdNtkFree( pExp0 ); if ( pExp1 ) Kit_DsdNtkFree( pExp1 ); return NULL; }
            Aig_Obj_t * pF0 = Phy_RewriteDsdToAig( pAig, pExp0, ppFanins, vMemory );
            Aig_Obj_t * pF1 = Phy_RewriteDsdToAig( pAig, pExp1, ppFanins, vMemory );
            Kit_DsdNtkFree( pExp0 ); Kit_DsdNtkFree( pExp1 );
            if ( pF0 == NULL || pF1 == NULL ) return NULL;
            Aig_Obj_t * pVar = ppFanins[ pCand->bestCofVar ];
            return Aig_Or( pAig,
                       Aig_And( pAig, pVar, pF1 ),
                       Aig_And( pAig, Aig_Not(pVar), pF0 ) );
        }
    default: return NULL;
    }
}

/* ---- Main entry point ---- */
int Phy_BalanceRun(
    Abc_Frame_t *  pAbc,
    Abc_Ntk_t *    pNtk,
    Phy_Data_t *   pData,
    int            Part,
    int            fVerbose )
{
    Aig_Man_t *    pAig;
    Aig_Obj_t *    pObj;
    Vec_Ptr_t *    vSupp;
    Vec_Ptr_t *    vNodesInt;
    Vec_Ptr_t *    vTruthElem;
    Vec_Ptr_t *    vTruthStore;
    Vec_Int_t *    vMemory;
    Mio_Library_t * pLib = NULL;
    int i, nLeaves, nMffc, nNodesBefore;
    int nAccept = 0, nScanned = 0, nSkipped = 0;
    int nPathPicked[4] = {0, 0, 0, 0};
    unsigned * pTruth;

    if ( pNtk == NULL || !Abc_NtkIsStrash( pNtk ) )
        return 0;

    if ( !Phy_fLutInit )
    {
        pLib = (Mio_Library_t *)Abc_FrameReadLibGen();
        Phy_RewriteInitLut( pLib );
    }

    pAig = Abc_NtkToDar( pNtk, 0, 0 );
    if ( pAig == NULL ) return 0;
    nNodesBefore = Aig_ManNodeNum( pAig );

    Aig_ManFanoutStart( pAig );

    vTruthElem  = Vec_PtrAllocTruthTables( 6 );
    vTruthStore = Vec_PtrAllocSimInfo( 1024, Kit_TruthWordNum( 6 ) );
    vMemory     = Vec_IntAlloc( 1 << 18 );
    vSupp       = Vec_PtrAlloc( 32 );
    vNodesInt   = Vec_PtrAlloc( 256 );

    Aig_ManForEachNodeReverse( pAig, pObj, i )
    {
        Phy_BalanceCand_t cand;
        Aig_Obj_t * pNewRoot;
        int minLeafLevel, mffcDepth, k;
        Aig_Obj_t * pLeaf;

        if ( !Aig_ObjIsNode( pObj ) ) continue;

        Vec_PtrClear( vSupp );
        nMffc   = Aig_NodeMffcSupp( pAig, pObj, 0, vSupp );
        nLeaves = Vec_PtrSize( vSupp );

        /* Target medium-to-large cones that could be unbalanced */
        if ( nMffc < 3 || nMffc > 15 ) { nSkipped++; continue; }
        if ( nLeaves < 2 || nLeaves > 6 ) { nSkipped++; continue; }

        /* Compute current MFFC internal depth (logic levels) */
        minLeafLevel = 999999;
        Vec_PtrForEachEntry( Aig_Obj_t *, vSupp, pLeaf, k )
        {
            int lev = (int)Aig_Regular(pLeaf)->Level;
            if ( lev < minLeafLevel ) minLeafLevel = lev;
        }
        if ( minLeafLevel >= (int)pObj->Level ) { nSkipped++; continue; }
        mffcDepth = (int)pObj->Level - minLeafLevel;

        /* Skip if already depth-optimal (1-2 levels can't be improved) */
        if ( mffcDepth <= 2 ) { nSkipped++; continue; }

        nScanned++;

        Vec_PtrClear( vNodesInt );
        Aig_ObjCollectCut( pObj, vSupp, vNodesInt );

        pTruth = Aig_ManCutTruth( pObj, vSupp, vNodesInt, vTruthElem, vTruthStore );
        if ( Kit_TruthIsConst0( pTruth, nLeaves ) || Kit_TruthIsConst1( pTruth, nLeaves ) )
            continue;

        /* Evaluate all three paths (depth-driven) */
        if ( !Phy_BalanceEvaluate( pTruth, nLeaves, mffcDepth, &cand, vMemory ) )
            continue;

        /* Structure guard: allow more nodes if depth improves */
        {
            int nGraphNodes;
            if ( cand.bestPath == PHY_BALANCE_PATH_ISOP )
            {
                int RetValue = Kit_TruthIsop( pTruth, nLeaves, vMemory, 1 );
                if ( RetValue == -1 ) continue;
                Kit_Graph_t * pGraph = Kit_SopFactor( vMemory, RetValue, nLeaves, vMemory );
                if ( pGraph == NULL ) continue;
                nGraphNodes = Kit_GraphNodeNum( pGraph );
                Kit_GraphFree( pGraph );
            }
            else if ( cand.bestPath == PHY_BALANCE_PATH_COF )
            {
                /* cof path builds two DSD trees + mux; skip guard for cof */
                nGraphNodes = nMffc;
            }
            else
            {
                Kit_DsdNtk_t * pNtk = Kit_DsdDecompose( pTruth, nLeaves );
                if ( pNtk == NULL ) continue;
                Kit_DsdNtk_t * pExp = Kit_DsdExpand( pNtk );
                Kit_DsdNtkFree( pNtk );
                if ( pExp == NULL ) continue;
                nGraphNodes = Kit_DsdCountAigNodes( pExp );
                Kit_DsdNtkFree( pExp );
            }
            /* Partition-aware depth-vs-area gating */
            {
                int depthImprove = mffcDepth - cand.bestDepth;
                int nodeBudget;
                if ( Part == 0 )  /* HIGH: aggressive for delay */
                {
                    if ( depthImprove >= 3 )      nodeBudget = nMffc + 3;
                    else if ( depthImprove >= 2 ) nodeBudget = nMffc + 2;
                    else if ( depthImprove >= 1 ) nodeBudget = nMffc + 1;
                    else                          nodeBudget = nMffc;
                }
                else if ( Part == 2 )  /* MID: balanced */
                {
                    if ( depthImprove >= 4 )      nodeBudget = nMffc + 2;
                    else if ( depthImprove >= 3 ) nodeBudget = nMffc + 1;
                    else if ( depthImprove >= 2 ) nodeBudget = nMffc;
                    else                          nodeBudget = nMffc - 1;
                }
                else  /* LOW: conservative on area */
                {
                    if ( depthImprove >= 5 )      nodeBudget = nMffc + 1;
                    else if ( depthImprove >= 4 ) nodeBudget = nMffc;
                    else if ( depthImprove >= 3 ) nodeBudget = nMffc - 1;
                    else                          nodeBudget = nMffc - 2;
                }
                if ( nGraphNodes > nodeBudget )
                    continue;
            }
        }

        nPathPicked[ cand.bestPath ]++;

        Aig_Obj_t ** ppFanins = (Aig_Obj_t **)Vec_PtrArray( vSupp );
        pNewRoot = Phy_BalanceBuildCandidate( pAig, ppFanins, pTruth, nLeaves, &cand, vMemory );

        if ( pNewRoot == NULL )
            continue;
        if ( pNewRoot == pObj || Aig_Regular(pNewRoot) == pObj )
            continue;

        Aig_ObjReplace( pAig, pObj, pNewRoot, 0 );
        nAccept++;
    }

    Aig_ManFanoutStop( pAig );
    Aig_ManCleanup( pAig );

    if ( nAccept > 0 )
    {
        Abc_Ntk_t * pNtkNew = Abc_NtkFromAigPhase( pAig );
        Aig_ManStop( pAig );
        if ( pNtkNew != NULL )
        {
            Abc_FrameReplaceCurrentNetwork( pAbc, pNtkNew );
            Cmd_CommandExecute( pAbc, "strash" );
        }
    }
    else
    {
        Aig_ManStop( pAig );
    }

    printf( "phy_balance: scanned=%d skipped=%d accepted=%d (of %d), base_delay=%.1f\n",
        nScanned, nSkipped, nAccept, nNodesBefore, Phy_BaseDelay );
    printf( "  paths: ISOP=%d DSD=%d cof=%d\n",
        nPathPicked[PHY_BALANCE_PATH_ISOP],
        nPathPicked[PHY_BALANCE_PATH_DSD],
        nPathPicked[PHY_BALANCE_PATH_COF] );

    Vec_PtrFree( vSupp );
    Vec_PtrFree( vNodesInt );
    Vec_PtrFree( vTruthElem );
    Vec_PtrFree( vTruthStore );
    Vec_IntFree( vMemory );

    return nAccept;
}

ABC_NAMESPACE_IMPL_END
