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

extern void         Phy_RewriteInitLut( Mio_Library_t * pLib );
extern float        Phy_RewriteScoreGraph( Kit_Graph_t * pGraph );
extern float        Phy_RewriteScoreDsd( Kit_DsdNtk_t * pNtk );
extern float        Phy_RewriteEstAigCost( int nAigNodes );
extern Aig_Obj_t *  Phy_RewriteDsdToAig( Aig_Man_t * pMan, Kit_DsdNtk_t * pNtk, Aig_Obj_t ** ppLeaves, Vec_Int_t * vMemory );

extern Aig_Obj_t *  Kit_GraphToAig( Aig_Man_t * pMan, Aig_Obj_t ** pFanins, Kit_Graph_t * pGraph );
extern Aig_Man_t *  Abc_NtkToDar( Abc_Ntk_t * pNtk, int fExors, int fRegisters );
extern Abc_Ntk_t *  Abc_NtkFromAigPhase( Aig_Man_t * pMan );

/* ---- Path flags ---- */
#define PHY_REFACTOR_PATH_NONE  0
#define PHY_REFACTOR_PATH_ISOP  1
#define PHY_REFACTOR_PATH_DSD   2
#define PHY_REFACTOR_PATH_COF   3

typedef struct
{
    int   bestPath;
    float bestCost;
    int   bestCompl;
    int   bestCofVar;
} Phy_RefactorCand_t;

/* ---- Three-path evaluation (same as rewrite, but for larger cones) ---- */
static int Phy_RefactorEvaluate(
    unsigned *           pTruth,
    int                  nLeaves,
    int                  nMffc,
    Phy_RefactorCand_t * pCand,
    Vec_Int_t *          vMemory )
{
    float oldCost    = Phy_RewriteEstAigCost( nMffc );
    float bestCost   = 1e12f;
    int   bestPath   = PHY_REFACTOR_PATH_NONE;
    int   bestCompl  = 0;
    int   bestCofVar = -1;
    int   nWords     = Kit_TruthWordNum( nLeaves );
    /* cofactor buffers: dynamic size for nLeaves up to 8 (nWords up to 8) */
    unsigned * pCof0 = (unsigned *)alloca( nWords * sizeof(unsigned) );
    unsigned * pCof1 = (unsigned *)alloca( nWords * sizeof(unsigned) );

    /* ---- Path 1: ISOP + factoring ---- */
    {
        int RetValue = Kit_TruthIsop( pTruth, nLeaves, vMemory, 1 );
        if ( RetValue != -1 )
        {
            Kit_Graph_t * pGraph = Kit_SopFactor( vMemory, RetValue, nLeaves, vMemory );
            if ( pGraph != NULL )
            {
                float cost = Phy_RewriteScoreGraph( pGraph );
                if ( cost < bestCost )
                {
                    bestCost  = cost;
                    bestPath  = PHY_REFACTOR_PATH_ISOP;
                    bestCompl = RetValue;
                }
                Kit_GraphFree( pGraph );
            }
        }
    }

    /* ---- Path 2: DSD decomposition ---- */
    {
        Kit_DsdNtk_t * pNtk = Kit_DsdDecompose( pTruth, nLeaves );
        if ( pNtk != NULL )
        {
            Kit_DsdNtk_t * pExp = Kit_DsdExpand( pNtk );
            Kit_DsdNtkFree( pNtk );
            if ( pExp != NULL )
            {
                float cost = Phy_RewriteScoreDsd( pExp );
                if ( cost < bestCost )
                {
                    bestCost  = cost;
                    bestPath  = PHY_REFACTOR_PATH_DSD;
                    bestCompl = 0;
                }
                Kit_DsdNtkFree( pExp );
            }
        }
    }

    /* ---- Path 3: Cofactoring search ---- */
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
            float cost0 = Phy_RewriteScoreDsd( pExp0 );
            float cost1 = Phy_RewriteScoreDsd( pExp1 );
            float costMux = 3.0f * Phy_BaseArea;
            Kit_DsdNtkFree( pExp0 ); Kit_DsdNtkFree( pExp1 );
            float total = cost0 + cost1 + costMux;
            if ( total < bestCost )
            {
                bestCost  = total;
                bestPath  = PHY_REFACTOR_PATH_COF;
                bestCofVar = v;
            }
        }
    }

    pCand->bestPath   = bestPath;
    pCand->bestCost   = bestCost;
    pCand->bestCompl  = bestCompl;
    pCand->bestCofVar = bestCofVar;

    return ( bestPath != PHY_REFACTOR_PATH_NONE && bestCost < oldCost - 1e-6f );
}

/* Build the winning candidate */
static Aig_Obj_t * Phy_RefactorBuildCandidate(
    Aig_Man_t *           pAig,
    Aig_Obj_t **          ppFanins,
    unsigned *            pTruth,
    int                   nLeaves,
    Phy_RefactorCand_t *  pCand,
    Vec_Int_t *           vMemory )
{
    Aig_Obj_t * pRoot;

    switch ( pCand->bestPath )
    {
    case PHY_REFACTOR_PATH_ISOP:
        {
            int RetValue = Kit_TruthIsop( pTruth, nLeaves, vMemory, 1 );
            if ( RetValue == -1 ) return NULL;
            Kit_Graph_t * pGraph = Kit_SopFactor( vMemory, RetValue, nLeaves, vMemory );
            if ( pGraph == NULL ) return NULL;
            pRoot = Kit_GraphToAig( pAig, ppFanins, pGraph );
            Kit_GraphFree( pGraph );
            if ( pRoot != NULL && RetValue )
                pRoot = Aig_Not( pRoot );
            return pRoot;
        }

    case PHY_REFACTOR_PATH_DSD:
        {
            Kit_DsdNtk_t * pNtk = Kit_DsdDecompose( pTruth, nLeaves );
            if ( pNtk == NULL ) return NULL;
            Kit_DsdNtk_t * pExp = Kit_DsdExpand( pNtk );
            Kit_DsdNtkFree( pNtk );
            if ( pExp == NULL ) return NULL;
            pRoot = Phy_RewriteDsdToAig( pAig, pExp, ppFanins, vMemory );
            Kit_DsdNtkFree( pExp );
            return pRoot;
        }

    case PHY_REFACTOR_PATH_COF:
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
int Phy_RefactorRun(
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

    /* For nLeaves up to 6: nWords = 2 */
    vTruthElem  = Vec_PtrAllocTruthTables( 6 );
    vTruthStore = Vec_PtrAllocSimInfo( 1024, Kit_TruthWordNum( 6 ) );
    vMemory     = Vec_IntAlloc( 1 << 18 );
    vSupp       = Vec_PtrAlloc( 32 );
    vNodesInt   = Vec_PtrAlloc( 512 );

    Aig_ManForEachNodeReverse( pAig, pObj, i )
    {
        Phy_RefactorCand_t cand;
        Aig_Obj_t ** ppFanins;
        Aig_Obj_t * pNewRoot;

        if ( !Aig_ObjIsNode( pObj ) ) continue;

        Vec_PtrClear( vSupp );
        nMffc   = Aig_NodeMffcSupp( pAig, pObj, 0, vSupp );
        nLeaves = Vec_PtrSize( vSupp );

        /* refactor: larger cones than rewrite (3-20 vs 2-10), more leaves (2-6) */
        if ( nMffc < 3 || nMffc > 20 ) { nSkipped++; continue; }
        if ( nLeaves < 2 || nLeaves > 6 ) { nSkipped++; continue; }

        nScanned++;

        Vec_PtrClear( vNodesInt );
        Aig_ObjCollectCut( pObj, vSupp, vNodesInt );

        pTruth = Aig_ManCutTruth( pObj, vSupp, vNodesInt, vTruthElem, vTruthStore );
        if ( Kit_TruthIsConst0( pTruth, nLeaves ) || Kit_TruthIsConst1( pTruth, nLeaves ) )
            continue;

        /* Evaluate all three paths */
        if ( !Phy_RefactorEvaluate( pTruth, nLeaves, nMffc, &cand, vMemory ) )
            continue;

        /* Structure size guard: tighter for larger cones (+2 vs +3) */
        {
            int nGraphNodes;
            if ( cand.bestPath == PHY_REFACTOR_PATH_ISOP )
            {
                int RetValue = Kit_TruthIsop( pTruth, nLeaves, vMemory, 1 );
                if ( RetValue == -1 ) continue;
                Kit_Graph_t * pGraph = Kit_SopFactor( vMemory, RetValue, nLeaves, vMemory );
                if ( pGraph == NULL ) continue;
                nGraphNodes = Kit_GraphNodeNum( pGraph );
                Kit_GraphFree( pGraph );
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
            /* Partition-aware area gating: tighter budget for non-critical */
            {
                int nodeBudget;
                if ( Part == 0 )      nodeBudget = nMffc + 3;  /* HIGH: delay priority */
                else if ( Part == 2 ) nodeBudget = nMffc + 1;  /* MID: balanced */
                else                  nodeBudget = nMffc;      /* LOW: area priority */
                if ( nGraphNodes > nodeBudget )
                    continue;
            }
        }

        nPathPicked[ cand.bestPath ]++;

        /* Build and replace */
        ppFanins = (Aig_Obj_t **)Vec_PtrArray( vSupp );
        pNewRoot = Phy_RefactorBuildCandidate( pAig, ppFanins, pTruth, nLeaves, &cand, vMemory );

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

    printf( "phy_refactor: scanned=%d skipped=%d accepted=%d (of %d), base=%.3f\n",
        nScanned, nSkipped, nAccept, nNodesBefore, Phy_BaseArea );
    printf( "  paths: ISOP=%d DSD=%d cof=%d\n",
        nPathPicked[PHY_REFACTOR_PATH_ISOP],
        nPathPicked[PHY_REFACTOR_PATH_DSD],
        nPathPicked[PHY_REFACTOR_PATH_COF] );

    Vec_PtrFree( vSupp );
    Vec_PtrFree( vNodesInt );
    Vec_PtrFree( vTruthElem );
    Vec_PtrFree( vTruthStore );
    Vec_IntFree( vMemory );

    return nAccept;
}

ABC_NAMESPACE_IMPL_END
