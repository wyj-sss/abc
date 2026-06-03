#include "opt/physical/phyOpt.h"
#include "opt/physical/phyInfo.h"
#include "bool/kit/kit.h"
#include "map/mio/mio.h"
#include "base/abc/abc.h"
#include "aig/aig/aig.h"

ABC_NAMESPACE_IMPL_START

extern Aig_Obj_t * Kit_GraphToAig( Aig_Man_t * pMan, Aig_Obj_t ** pFanins, Kit_Graph_t * pGraph );
extern Aig_Obj_t * Kit_GraphToAigInternal( Aig_Man_t * pMan, Kit_Graph_t * pGraph );

extern Aig_Man_t * Abc_NtkToDar( Abc_Ntk_t * pNtk, int fExors, int fRegisters );
extern Abc_Ntk_t * Abc_NtkFromAigPhase( Aig_Man_t * pMan );

/* ---- Gate cost LUT: 4-bit truth table -> min library cell area ---- */

Phy_GateCostLut_t Phy_GateCostLut[16];
int               Phy_fLutInit = 0;
float             Phy_BaseArea  = 1.0f;
float             Phy_BaseDelay = 100.0f;  /* will be set from library */

void Phy_RewriteInitLut( Mio_Library_t * pLib )
{
    Mio_Gate_t * pGate;
    int i, tt;

    for ( i = 0; i < 16; i++ )
    {
        Phy_GateCostLut[i].area  = 1.0f;
        Phy_GateCostLut[i].delay = 1e9f;
    }
    Phy_fLutInit = 1;

    if ( pLib == NULL ) return;

    Mio_LibraryForEachGate( pLib, pGate )
    {
        if ( Mio_GateReadPinNum( pGate ) != 2 ) continue;
        tt = (int)( Mio_GateReadTruth( pGate ) & 0xF );
        float area  = (float)Mio_GateReadArea( pGate );
        float delay = (float)Mio_GateReadDelayMax( pGate );
        if ( area < Phy_GateCostLut[tt].area || Phy_GateCostLut[tt].area == 1.0f )
            Phy_GateCostLut[tt].area = area;
        if ( delay < Phy_GateCostLut[tt].delay )
            Phy_GateCostLut[tt].delay = delay;
    }

    /* NAND2 truth table = 0x7 (0111): !(a&b) */
    /* AIG AND node cost: AND2 cell (truth table 0x8) */
    Phy_BaseArea  = Phy_GateCostLut[0x8].area;
    Phy_BaseDelay = Phy_GateCostLut[0x8].delay;

    /* Fill ambiguities */
    Phy_GateCostLut[0x0].area = Phy_GateCostLut[0x0].delay = 0.0f;
    Phy_GateCostLut[0xF].area = Phy_GateCostLut[0xF].delay = 0.0f;

    printf( "phy_rewrite LUT: AND2=%.3f/%.1fps NAND2=%.3f/%.1fps OR2=%.3f/%.1fps NOR2=%.3f/%.1fps XOR2=%.3f/%.1fps\n",
        Phy_GateCostLut[0x8].area, Phy_GateCostLut[0x8].delay,
        Phy_GateCostLut[0x7].area, Phy_GateCostLut[0x7].delay,
        Phy_GateCostLut[0xE].area, Phy_GateCostLut[0xE].delay,
        Phy_GateCostLut[0x1].area, Phy_GateCostLut[0x1].delay,
        Phy_GateCostLut[0x6].area, Phy_GateCostLut[0x6].delay );
    fflush(stdout);
}

/* Compute the 2-input truth table of a Kit_Node */
static int Phy_RewriteNodeTT( int fNodeOr, int fCompl0, int fCompl1 )
{
    int tt = 0, a, b;
    for ( a = 0; a < 2; a++ )
        for ( b = 0; b < 2; b++ )
        {
            int in0 = a ^ fCompl0;
            int in1 = b ^ fCompl1;
            int out = fNodeOr ? (in0 | in1) : (in0 & in1);
            if ( out ) tt |= ( 1 << ( (a << 1) | b ) );
        }
    return tt;
}

static float Phy_RewriteNodeCost( int fNodeOr, int fCompl0, int fCompl1 )
{
    return Phy_GateCostLut[ Phy_RewriteNodeTT( fNodeOr, fCompl0, fCompl1 ) ].area;
}

/* Score a Kit_Graph_t with physical (library cell) area */
float Phy_RewriteScoreGraph( Kit_Graph_t * pGraph )
{
    Kit_Node_t * pNode;
    float total = 0.0f;
    int i;

    if ( pGraph == NULL ) return 1e12f;

    for ( i = pGraph->nLeaves; i < pGraph->nSize; i++ )
    {
        pNode = pGraph->pNodes + i;
        total += Phy_RewriteNodeCost( pNode->fNodeOr, pNode->fCompl0, pNode->fCompl1 );
    }

    return total;
}

/* Estimate physical cost of existing AIG: each AND node ~ 1 NAND2 cell */
float Phy_RewriteEstAigCost( int nAigNodes )
{
    return (float)nAigNodes * Phy_BaseArea;
}

/* ---- DSD physical cost scoring ---- */

float Phy_RewriteScoreDsd( Kit_DsdNtk_t * pNtk )
{
    Kit_DsdObj_t * pObj;
    float total = 0.0f;
    int i;

    if ( pNtk == NULL ) return 1e12f;

    for ( i = 0; i < pNtk->nNodes; i++ )
    {
        pObj = pNtk->pNodes[i];
        if ( pObj->Type == KIT_DSD_AND )
            total += (float)(pObj->nFans - 1) * Phy_GateCostLut[0x8].area; /* AND2 */
        else if ( pObj->Type == KIT_DSD_XOR )
            total += (float)(pObj->nFans - 1) * Phy_GateCostLut[0x6].area; /* XOR2 */
        else if ( pObj->Type == KIT_DSD_PRIME )
            total += 3.0f * Phy_BaseArea; /* ~3 NAND2 for MUX */
    }
    return total;
}

/* ---- DSD tree -> AIG builder ---- */

/* Build 2-input XOR from AIG gates: XOR = (a AND !b) OR (!a AND b) */
static Aig_Obj_t * Phy_RewriteXor2( Aig_Man_t * pMan, Aig_Obj_t * pA, Aig_Obj_t * pB )
{
    Aig_Obj_t * pN1 = Aig_And( pMan, Aig_Not(pA), pB );
    Aig_Obj_t * pN2 = Aig_And( pMan, pA, Aig_Not(pB) );
    return Aig_Or( pMan, pN2, pN1 );
}

/* Recursively build AIG for a DSD subtree. Id is a DSD variable-index (NOT a literal). */
static Aig_Obj_t * Phy_RewriteDsdBuild_rec(
    Aig_Man_t *      pMan,
    Kit_DsdNtk_t *   pNtk,
    int              Id,
    Aig_Obj_t **     ppLeaves,
    Vec_Int_t *      vMemory )
{
    Kit_DsdObj_t * pObj;
    Kit_Graph_t * pGraph;
    unsigned * pTruth;
    unsigned iLit;
    int i, nFans;

    if ( Id < pNtk->nVars )
        return ppLeaves[Id];

    pObj  = pNtk->pNodes[Id - pNtk->nVars];
    nFans = (int)pObj->nFans;

    if ( pObj->Type == KIT_DSD_AND )
    {
        Aig_Obj_t * pResult = NULL;
        Kit_DsdObjForEachFanin( pNtk, pObj, iLit, i )
        {
            Aig_Obj_t * pChild = Phy_RewriteDsdBuild_rec( pMan, pNtk, Abc_Lit2Var(iLit), ppLeaves, vMemory );
            pChild = Aig_NotCond( pChild, Abc_LitIsCompl(iLit) );
            pResult = (pResult == NULL) ? pChild : Aig_And( pMan, pResult, pChild );
        }
        return pResult;
    }
    else if ( pObj->Type == KIT_DSD_XOR )
    {
        Aig_Obj_t * pResult = NULL;
        Kit_DsdObjForEachFanin( pNtk, pObj, iLit, i )
        {
            Aig_Obj_t * pChild = Phy_RewriteDsdBuild_rec( pMan, pNtk, Abc_Lit2Var(iLit), ppLeaves, vMemory );
            pChild = Aig_NotCond( pChild, Abc_LitIsCompl(iLit) );
            pResult = (pResult == NULL) ? pChild : Phy_RewriteXor2( pMan, pResult, pChild );
        }
        return pResult;
    }
    else if ( pObj->Type == KIT_DSD_PRIME )
    {
        Aig_Obj_t * pPrimeFanins[8];
        Aig_Obj_t * pResult;

        pTruth = Kit_DsdObjTruth( pObj );
        if ( pTruth == NULL || nFans > 5 )
            return NULL;

        Kit_DsdObjForEachFanin( pNtk, pObj, iLit, i )
        {
            Aig_Obj_t * pChild = Phy_RewriteDsdBuild_rec( pMan, pNtk, Abc_Lit2Var(iLit), ppLeaves, vMemory );
            pPrimeFanins[i] = Aig_NotCond( pChild, Abc_LitIsCompl(iLit) );
        }

        pGraph = Kit_TruthToGraph( pTruth, nFans, vMemory );
        if ( pGraph == NULL )
            return NULL;

        {
            Kit_Node_t * pLeaf;
            int k;
            Kit_GraphForEachLeaf( pGraph, pLeaf, k )
                pLeaf->pFunc = pPrimeFanins[k];
        }

        pResult = Kit_GraphToAigInternal( pMan, pGraph );
        Kit_GraphFree( pGraph );
        return pResult;
    }
    /* KIT_DSD_CONST1 or KIT_DSD_VAR should not appear as internal nodes */
    return NULL;
}

/* Build AIG from a complete DSD tree. Returns the root AIG object. */
Aig_Obj_t * Phy_RewriteDsdToAig(
    Aig_Man_t *      pMan,
    Kit_DsdNtk_t *   pNtk,
    Aig_Obj_t **     ppLeaves,
    Vec_Int_t *      vMemory )
{
    Aig_Obj_t * pRoot;
    int RootId;

    if ( pNtk == NULL || pNtk->nNodes == 0 )
    {
        /* Constant or variable-only: shouldn't happen after filtering */
        return NULL;
    }

    RootId = Abc_Lit2Var( pNtk->Root );
    pRoot  = Phy_RewriteDsdBuild_rec( pMan, pNtk, RootId, ppLeaves, vMemory );

    if ( pRoot != NULL && Abc_LitIsCompl( pNtk->Root ) )
        pRoot = Aig_Not( pRoot );

    return pRoot;
}

/* ---- Three-path candidate evaluation ---- */

#define PHY_REWRITE_PATH_NONE  0
#define PHY_REWRITE_PATH_ISOP  1
#define PHY_REWRITE_PATH_DSD   2
#define PHY_REWRITE_PATH_COF   3

typedef struct
{
    int   bestPath;
    float bestCost;
    int   bestCompl;  /* ISOP: RetValue; DSD: Root complement is in DSD tree */
    int   bestCofVar; /* Cofactoring: which variable */
} Phy_RewriteCand_t;

/* Evaluate all three paths, fill candidate with best result.
 * Returns 1 if any candidate beats the current AIG cost. */
static int Phy_RewriteEvaluate(
    unsigned *          pTruth,
    int                 nLeaves,
    int                 nMffc,
    Phy_RewriteCand_t * pCand,
    Vec_Int_t *         vMemory )
{
    float oldCost    = Phy_RewriteEstAigCost( nMffc );
    float bestCost   = 1e12f;
    int   bestPath   = PHY_REWRITE_PATH_NONE;
    int   bestCompl  = 0;
    int   bestCofVar = -1;

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
                    bestPath  = PHY_REWRITE_PATH_ISOP;
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
            pNtk = pExp;

            if ( pNtk != NULL )
            {
                float cost = Phy_RewriteScoreDsd( pNtk );
                if ( cost < bestCost )
                {
                    bestCost  = cost;
                    bestPath  = PHY_REWRITE_PATH_DSD;
                    bestCompl = 0; /* DSD root complement handled via pNtk->Root */
                }
                Kit_DsdNtkFree( pNtk );
            }
        }
    }

    /* ---- Path 3: Cofactoring search ---- */
    {
        unsigned pCof0[2], pCof1[2];
        int v;

        for ( v = 0; v < nLeaves; v++ )
        {
            Kit_DsdNtk_t * pNtk0, * pNtk1, * pExp;
            float cost0, cost1, costMux;

            Kit_TruthCofactor0New( pCof0, pTruth, nLeaves, v );
            Kit_TruthCofactor1New( pCof1, pTruth, nLeaves, v );

            /* Skip if either cofactor is all-don't-care (shouldn't happen) */
            if ( ( Kit_TruthIsConst0( pCof0, nLeaves ) || Kit_TruthIsConst1( pCof0, nLeaves ) ) &&
                 ( Kit_TruthIsConst0( pCof1, nLeaves ) || Kit_TruthIsConst1( pCof1, nLeaves ) ) )
                continue;

            pNtk0 = Kit_DsdDecompose( pCof0, nLeaves );
            pNtk1 = Kit_DsdDecompose( pCof1, nLeaves );

            if ( pNtk0 == NULL || pNtk1 == NULL )
            {
                if ( pNtk0 ) Kit_DsdNtkFree( pNtk0 );
                if ( pNtk1 ) Kit_DsdNtkFree( pNtk1 );
                continue;
            }

            pExp  = Kit_DsdExpand( pNtk0 );
            Kit_DsdNtkFree( pNtk0 );
            pNtk0 = pExp;

            pExp  = Kit_DsdExpand( pNtk1 );
            Kit_DsdNtkFree( pNtk1 );
            pNtk1 = pExp;

            if ( pNtk0 == NULL || pNtk1 == NULL )
            {
                if ( pNtk0 ) Kit_DsdNtkFree( pNtk0 );
                if ( pNtk1 ) Kit_DsdNtkFree( pNtk1 );
                continue;
            }

            cost0   = Phy_RewriteScoreDsd( pNtk0 );
            cost1   = Phy_RewriteScoreDsd( pNtk1 );
            costMux = 3.0f * Phy_BaseArea; /* MUX overhead: ~3 NAND2 */

            Kit_DsdNtkFree( pNtk0 );
            Kit_DsdNtkFree( pNtk1 );

            {
                float total = cost0 + cost1 + costMux;
                if ( total < bestCost )
                {
                    bestCost  = total;
                    bestPath  = PHY_REWRITE_PATH_COF;
                    bestCofVar = v;
                }
            }
        }
    }

    pCand->bestPath  = bestPath;
    pCand->bestCost  = bestCost;
    pCand->bestCompl = bestCompl;
    pCand->bestCofVar = bestCofVar;

    return ( bestPath != PHY_REWRITE_PATH_NONE && bestCost < oldCost - 1e-6f );
}

/* Build the winning candidate into AIG. Returns the new root (may be complemented).
 * BUFs created by Aig_ObjReplace with complemented roots are cleaned up
 * by Phy_RewriteEliminateBufs after the replacement loop. */
static Aig_Obj_t * Phy_RewriteBuildCandidate(
    Aig_Man_t *          pAig,
    Aig_Obj_t **         ppFanins,
    unsigned *           pTruth,
    int                  nLeaves,
    Phy_RewriteCand_t *  pCand,
    Vec_Int_t *          vMemory )
{
    Aig_Obj_t * pRoot;

    switch ( pCand->bestPath )
    {
    case PHY_REWRITE_PATH_ISOP:
        {
            int RetValue = Kit_TruthIsop( pTruth, nLeaves, vMemory, 1 );
            if ( RetValue == -1 ) return NULL;

            Kit_Graph_t * pGraph = Kit_SopFactor( vMemory, RetValue, nLeaves, vMemory );
            if ( pGraph == NULL ) return NULL;

            pRoot = Kit_GraphToAig( pAig, ppFanins, pGraph );
            Kit_GraphFree( pGraph );
            if ( pRoot != NULL && RetValue )
                pRoot = Aig_Not( pRoot );
            break;
        }

    case PHY_REWRITE_PATH_DSD:
        {
            Kit_DsdNtk_t * pNtk = Kit_DsdDecompose( pTruth, nLeaves );
            if ( pNtk == NULL ) return NULL;

            Kit_DsdNtk_t * pExp = Kit_DsdExpand( pNtk );
            Kit_DsdNtkFree( pNtk );
            if ( pExp == NULL ) return NULL;

            pRoot = Phy_RewriteDsdToAig( pAig, pExp, ppFanins, vMemory );
            Kit_DsdNtkFree( pExp );
            break;
        }

    case PHY_REWRITE_PATH_COF:
        {
            unsigned pCof0[2], pCof1[2];
            Kit_TruthCofactor0New( pCof0, pTruth, nLeaves, pCand->bestCofVar );
            Kit_TruthCofactor1New( pCof1, pTruth, nLeaves, pCand->bestCofVar );

            Kit_DsdNtk_t * pNtk0 = Kit_DsdDecompose( pCof0, nLeaves );
            Kit_DsdNtk_t * pNtk1 = Kit_DsdDecompose( pCof1, nLeaves );
            if ( pNtk0 == NULL || pNtk1 == NULL )
            {
                if ( pNtk0 ) Kit_DsdNtkFree( pNtk0 );
                if ( pNtk1 ) Kit_DsdNtkFree( pNtk1 );
                return NULL;
            }

            Kit_DsdNtk_t * pExp0 = Kit_DsdExpand( pNtk0 );
            Kit_DsdNtk_t * pExp1 = Kit_DsdExpand( pNtk1 );
            Kit_DsdNtkFree( pNtk0 );
            Kit_DsdNtkFree( pNtk1 );

            if ( pExp0 == NULL || pExp1 == NULL )
            {
                if ( pExp0 ) Kit_DsdNtkFree( pExp0 );
                if ( pExp1 ) Kit_DsdNtkFree( pExp1 );
                return NULL;
            }

            Aig_Obj_t * pF0 = Phy_RewriteDsdToAig( pAig, pExp0, ppFanins, vMemory );
            Aig_Obj_t * pF1 = Phy_RewriteDsdToAig( pAig, pExp1, ppFanins, vMemory );
            Kit_DsdNtkFree( pExp0 );
            Kit_DsdNtkFree( pExp1 );

            if ( pF0 == NULL || pF1 == NULL )
                return NULL;

            Aig_Obj_t * pVar = ppFanins[ pCand->bestCofVar ];

            /* MUX: (var AND f1) OR (NOT(var) AND f0) */
            pRoot = Aig_Or( pAig,
                       Aig_And( pAig, pVar, pF1 ),
                       Aig_And( pAig, Aig_Not(pVar), pF0 ) );
            break;
        }

    default:
        return NULL;
    }

    return pRoot;
}

/* ---- Main entry point ---- */
int Phy_RewriteRun(
    Abc_Frame_t *  pAbc,
    Abc_Ntk_t *    pNtk,
    Phy_Data_t *   pData,
    int            Part,
    int            fVerbose )
{
    Aig_Man_t *  pAig;
    Aig_Obj_t *  pObj;
    Vec_Ptr_t *  vSupp;
    Vec_Ptr_t *  vNodesInt;
    Vec_Ptr_t *  vTruthElem;
    Vec_Ptr_t *  vTruthStore;
    Vec_Int_t *  vMemory;
    Mio_Library_t * pLib = NULL;
    int i, nLeaves, nMffc, nNodesBefore;
    int nAccept = 0, nScanned = 0, nSkipped = 0, nConfirmed = 0;
    int nPathPicked[4] = {0, 0, 0, 0}; /* counts per path */
    unsigned * pTruth;

    if ( pNtk == NULL || !Abc_NtkIsStrash( pNtk ) )
        return 0;

    printf( "phy_rewrite: ENTER nNodes=%d\n", Abc_NtkNodeNum(pNtk) ); fflush(stdout);

    if ( !Phy_fLutInit )
    {
        pLib = (Mio_Library_t *)Abc_FrameReadLibGen();
        Phy_RewriteInitLut( pLib );
    }

    pAig = Abc_NtkToDar( pNtk, 0, 0 );
    if ( pAig == NULL ) return 0;

    nNodesBefore = Aig_ManNodeNum( pAig );

    /* Set up fanout data so Aig_ObjReplace works correctly */
    Aig_ManFanoutStart( pAig );

    vTruthElem  = Vec_PtrAllocTruthTables( 5 );
    vTruthStore = Vec_PtrAllocSimInfo( 1024, Kit_TruthWordNum( 5 ) );
    vMemory     = Vec_IntAlloc( 1 << 18 );
    vSupp       = Vec_PtrAlloc( 32 );
    vNodesInt   = Vec_PtrAlloc( 256 );

    Aig_ManForEachNodeReverse( pAig, pObj, i )
    {
        Phy_RewriteCand_t cand;
        Aig_Obj_t ** ppFanins;
        Aig_Obj_t * pNewRoot;

        if ( !Aig_ObjIsNode( pObj ) ) continue;

        Vec_PtrClear( vSupp );
        nMffc   = Aig_NodeMffcSupp( pAig, pObj, 0, vSupp );
        nLeaves = Vec_PtrSize( vSupp );

        if ( nMffc < 2 || nMffc > 10 ) { nSkipped++; continue; }
        if ( nLeaves < 2 || nLeaves > 5 ) { nSkipped++; continue; }

        nScanned++;

        Vec_PtrClear( vNodesInt );
        Aig_ObjCollectCut( pObj, vSupp, vNodesInt );

        pTruth = Aig_ManCutTruth( pObj, vSupp, vNodesInt, vTruthElem, vTruthStore );

        if ( Kit_TruthIsConst0( pTruth, nLeaves ) || Kit_TruthIsConst1( pTruth, nLeaves ) )
            continue;

        /* Evaluate all three paths, pick the best */
        if ( !Phy_RewriteEvaluate( pTruth, nLeaves, nMffc, &cand, vMemory ) )
            continue;

        /* Accept only if structure size doesn't explode */
        {
            int nGraphNodes;
            if ( cand.bestPath == PHY_REWRITE_PATH_ISOP )
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
                /* For DSD/cofactoring, use AIG node count estimate from DSD tree */
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

        /* Build the winning candidate */
        ppFanins = (Aig_Obj_t **)Vec_PtrArray( vSupp );
        pNewRoot = Phy_RewriteBuildCandidate( pAig, ppFanins, pTruth, nLeaves, &cand, vMemory );

        if ( pNewRoot == NULL )
            continue;

        /* Check if the new root is actually different from the original */
        if ( pNewRoot == pObj || Aig_Regular(pNewRoot) == pObj )
        {
            nConfirmed++;
            continue;
        }

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

    printf( "phy_rewrite: scanned=%d skipped=%d accepted=%d confirmed=%d (of %d), base=%.3f\n",
        nScanned, nSkipped, nAccept, nConfirmed, nNodesBefore, Phy_BaseArea );
    printf( "  paths: ISOP=%d DSD=%d cof=%d\n",
        nPathPicked[PHY_REWRITE_PATH_ISOP],
        nPathPicked[PHY_REWRITE_PATH_DSD],
        nPathPicked[PHY_REWRITE_PATH_COF] );

    Vec_PtrFree( vSupp );
    Vec_PtrFree( vNodesInt );
    Vec_PtrFree( vTruthElem );
    Vec_PtrFree( vTruthStore );
    Vec_IntFree( vMemory );

    return nAccept;
}

ABC_NAMESPACE_IMPL_END
