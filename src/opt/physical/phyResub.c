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
#define PHY_RESUB_PATH_NONE   0
#define PHY_RESUB_PATH_ISOP   1
#define PHY_RESUB_PATH_DSD    2
#define PHY_RESUB_PATH_COF    3
#define PHY_RESUB_PATH_DIV    4  /* divisor-based replacement */

typedef struct
{
    int   bestPath;
    float bestCost;
    int   bestCompl;
    int   bestCofVar;
    int   bestDivId;   /* divisor node index in vNodesInt */
    int   bestLeafId;  /* leaf index, or -1 for no-leaf (direct/invert match) */
    int   bestGateTT;  /* 2-input truth table for divisor+leaf combo, or -1 for direct */
    int   bestFComplD; /* divisor complemented? */
    int   bestFComplL; /* leaf complemented? */
} Phy_ResubCand_t;

/* ---- Divisor-based evaluation ---- */

/* Check if T == truth(D) combined with leaf Li via a 2-input gate.
 * pTemp must be a pre-allocated truth table buffer (nWords). */
static int Phy_ResubCheckDivLeaf(
    unsigned * pT,       /* target truth table */
    unsigned * pD,       /* divisor truth table */
    unsigned * pL,       /* leaf truth table */
    unsigned * pTemp,    /* temp buffer */
    int        nWords,
    int      * pGateTT,  /* out: 2-input gate truth table */
    int      * pFComplD, /* out: divisor complemented? */
    int      * pFComplL) /* out: leaf complemented? */
{
    int fcd, fcl;
    /* Try all 4 complement combinations for AND/OR/NAND/NOR */
    for ( fcd = 0; fcd <= 1; fcd++ )
    for ( fcl = 0; fcl <= 1; fcl++ )
    {
        unsigned * pDc, * pLc;

        /* AND: fcd -> !D, fcl -> !L, gate = AND( Dc, Lc ) */
        if ( fcd ) Kit_TruthNot( pTemp, pD, nWords );
        else       Kit_TruthCopy( pTemp, pD, nWords );
        pDc = fcd ? pTemp : pTemp;
        if ( fcl ) { Kit_TruthNot( pTemp + nWords, pL, nWords ); pLc = pTemp + nWords; }
        else       pLc = (unsigned *)pL;

        if ( fcd && fcl ) { Kit_TruthAnd( pTemp + 2*nWords, pDc, pLc, nWords );
                            if ( Kit_TruthIsEqual( pT, pTemp + 2*nWords, nWords ) )
                                { *pGateTT = 0x8; *pFComplD = fcd; *pFComplL = fcl; return 1; } }
        else { Kit_TruthAnd( pTemp + 2*nWords, pDc, pLc, nWords ); }

        if ( Kit_TruthIsEqual( pT, pTemp + 2*nWords, nWords ) )
            { *pGateTT = 0x8; *pFComplD = fcd; *pFComplL = fcl; return 1; }

        /* NAND */
        Kit_TruthNot( pTemp + 2*nWords, pTemp + 2*nWords, nWords );
        if ( Kit_TruthIsEqual( pT, pTemp + 2*nWords, nWords ) )
            { *pGateTT = 0x7; *pFComplD = fcd; *pFComplL = fcl; return 1; }

        /* OR: OR(Dc, Lc) */
        Kit_TruthOr( pTemp + 2*nWords, pDc, pLc, nWords );
        if ( Kit_TruthIsEqual( pT, pTemp + 2*nWords, nWords ) )
            { *pGateTT = 0xE; *pFComplD = fcd; *pFComplL = fcl; return 1; }

        /* NOR */
        Kit_TruthNot( pTemp + 2*nWords, pTemp + 2*nWords, nWords );
        if ( Kit_TruthIsEqual( pT, pTemp + 2*nWords, nWords ) )
            { *pGateTT = 0x1; *pFComplD = fcd; *pFComplL = fcl; return 1; }

        /* XOR: XOR(Dc, Lc) */
        Kit_TruthXor( pTemp + 2*nWords, pDc, pLc, nWords );
        if ( Kit_TruthIsEqual( pT, pTemp + 2*nWords, nWords ) )
            { *pGateTT = 0x6; *pFComplD = fcd; *pFComplL = fcl; return 1; }
    }
    return 0;
}

/* Evaluate divisor-based candidates. Returns 1 if found, fills pCand. */
static int Phy_ResubEvaluateDivisors(
    unsigned *        pTruth,     /* target truth table */
    int               nLeaves,
    unsigned **       ppDivTruths, /* divisor truth tables (from vNodesInt) */
    int               nDivs,      /* number of divisors */
    unsigned **       ppLeafTTs,  /* leaf truth tables (elementary vars) */
    int               nMffc,
    unsigned *        pTemp,      /* temp buffer: need 3 * nWords */
    int               nWords,
    Phy_ResubCand_t * pCand )
{
    /* oldCost: nMffc-1 because divisor stays in the network
     * (only pObj and intermediate nodes between divisor→pObj are removed) */
    float oldCost = Phy_RewriteEstAigCost( nMffc > 1 ? nMffc - 1 : 1 );
    float bestCost = oldCost - 1e-6f;
    int   bestDivId  = -1;
    int   bestLeafId = -1;
    int   bestGateTT = -1;
    int   bestFComplD = 0;
    int   bestFComplL = 0;
    int   found = 0;
    int   d, l;

    /* Skip last divisor = target node itself (nDivs-1 is always pObj) */
    for ( d = 0; d < nDivs - 1; d++ )
    {
        unsigned * pD = ppDivTruths[d];
        if ( pD == NULL ) continue;

        /* Type 1: direct match (wire) — cost = 0 */
        if ( Kit_TruthIsEqual( pTruth, pD, nWords ) )
        {
            if ( 0.0f < bestCost )
            {
                bestCost  = 0.0f;
                bestDivId  = d;
                bestLeafId = -1;
                bestGateTT = -1;
                bestFComplD = 0;
                bestFComplL = 0;
                found = 1;
                break; /* can't beat 0 cost */
            }
        }
        /* Type 2: inverted match — cost = INV area (use LUT[0x3] for INV/buffer) */
        Kit_TruthNot( pTemp, pD, nWords );
        if ( Kit_TruthIsEqual( pTruth, pTemp, nWords ) )
        {
            float invCost = Phy_GateCostLut[0x3].area;
            if ( invCost < bestCost )
            {
                bestCost  = invCost;
                bestDivId  = d;
                bestLeafId = -1;
                bestGateTT = 0x3;
                bestFComplD = 1;
                bestFComplL = 0;
                found = 1;
            }
        }

        /* Types 3-7: divisor combined with a leaf via 2-input gate */
        for ( l = 0; l < nLeaves; l++ )
        {
            int gateTT, fComplD, fComplL;
            if ( !Phy_ResubCheckDivLeaf( pTruth, pD, ppLeafTTs[l],
                                         pTemp + nWords, nWords,
                                         &gateTT, &fComplD, &fComplL ) )
                continue;
            float gCost = Phy_GateCostLut[ gateTT ].area;
            if ( gCost < bestCost )
            {
                bestCost   = gCost;
                bestDivId  = d;
                bestLeafId = l;
                bestGateTT = gateTT;
                bestFComplD = fComplD;
                bestFComplL = fComplL;
                found = 1;
            }
        }
    }

    if ( !found ) return 0;

    pCand->bestPath   = PHY_RESUB_PATH_DIV;
    pCand->bestCost   = bestCost;
    pCand->bestDivId  = bestDivId;
    pCand->bestLeafId = bestLeafId;
    pCand->bestGateTT = bestGateTT;
    pCand->bestFComplD = bestFComplD;
    pCand->bestFComplL = bestFComplL;
    return 1;
}

/* ---- Combined evaluation (3 decomposition paths + divisor path) ---- */

static int Phy_ResubEvaluate(
    unsigned *        pTruth,
    int               nLeaves,
    int               nMffc,
    unsigned **       ppDivTruths,
    int               nDivs,
    unsigned **       ppLeafTTs,
    unsigned *        pTemp,
    int               nWords,
    Phy_ResubCand_t * pCand,
    Vec_Int_t *       vMemory )
{
    float oldCost  = Phy_RewriteEstAigCost( nMffc );
    float bestCost = 1e12f;
    int   bestPath = PHY_RESUB_PATH_NONE;
    int   bestCompl = 0;
    int   bestCofVar = -1;
    int   bestDivId = -1, bestLeafId = -1, bestGateTT = -1;
    int   bestFComplD = 0, bestFComplL = 0;

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
                    bestPath  = PHY_RESUB_PATH_ISOP;
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
                    bestPath  = PHY_RESUB_PATH_DSD;
                    bestCompl = 0;
                }
                Kit_DsdNtkFree( pExp );
            }
        }
    }

    /* ---- Path 3: Cofactoring search ---- */
    {
        unsigned pCof0[2], pCof1[2];
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
                bestPath  = PHY_RESUB_PATH_COF;
                bestCofVar = v;
            }
        }
    }

    /* ---- Path 4: Divisor-based replacement ---- */
    {
        Phy_ResubCand_t divCand;
        if ( Phy_ResubEvaluateDivisors( pTruth, nLeaves, ppDivTruths, nDivs,
                                         ppLeafTTs, nMffc, pTemp, nWords, &divCand ) )
        {
            if ( divCand.bestCost < bestCost )
            {
                bestCost   = divCand.bestCost;
                bestPath   = PHY_RESUB_PATH_DIV;
                bestDivId  = divCand.bestDivId;
                bestLeafId = divCand.bestLeafId;
                bestGateTT = divCand.bestGateTT;
                bestFComplD = divCand.bestFComplD;
                bestFComplL = divCand.bestFComplL;
            }
        }
    }

    pCand->bestPath   = bestPath;
    pCand->bestCost   = bestCost;
    pCand->bestCompl  = bestCompl;
    pCand->bestCofVar = bestCofVar;
    pCand->bestDivId  = bestDivId;
    pCand->bestLeafId = bestLeafId;
    pCand->bestGateTT = bestGateTT;
    pCand->bestFComplD = bestFComplD;
    pCand->bestFComplL = bestFComplL;

    /* For DIV path, divisor stays in network → effective savings is nMffc-1 */
    if ( bestPath == PHY_RESUB_PATH_DIV )
        oldCost = Phy_RewriteEstAigCost( nMffc > 1 ? nMffc - 1 : 1 );

    if ( bestPath != PHY_RESUB_PATH_NONE && bestCost >= oldCost - 1e-6f )
        return 0;

    return ( bestPath != PHY_RESUB_PATH_NONE );
}

/* ---- Build winning candidate ---- */

static Aig_Obj_t * Phy_ResubBuildCandidate(
    Aig_Man_t *         pAig,
    Aig_Obj_t **        ppFanins,
    unsigned *          pTruth,
    int                 nLeaves,
    Aig_Obj_t **        ppDivObjs,  /* divisor AIG objects (from vNodesInt) */
    Phy_ResubCand_t *   pCand,
    Vec_Int_t *         vMemory )
{
    Aig_Obj_t * pDiv, * pLeaf, * pRoot;
    Aig_Obj_t * pDc, * pLc;

    switch ( pCand->bestPath )
    {
    case PHY_RESUB_PATH_ISOP:
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

    case PHY_RESUB_PATH_DSD:
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

    case PHY_RESUB_PATH_COF:
        {
            unsigned pCof0[2], pCof1[2];
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

    case PHY_RESUB_PATH_DIV:
        {
            pDiv  = ppDivObjs[ pCand->bestDivId ];
            if ( pDiv == NULL ) return NULL;

            /* Direct match (wire) */
            if ( pCand->bestLeafId < 0 && pCand->bestGateTT < 0 )
                return pDiv;

            /* Inverted match */
            if ( pCand->bestLeafId < 0 && pCand->bestGateTT == 0x3 )
                return Aig_Not( pDiv );

            /* Divisor + leaf combination via 2-input gate */
            pDc = pCand->bestFComplD ? Aig_Not(pDiv) : pDiv;
            pLeaf = ppFanins[ pCand->bestLeafId ];
            pLc = pCand->bestFComplL ? Aig_Not(pLeaf) : pLeaf;

            switch ( pCand->bestGateTT )
            {
            case 0x8: return Aig_And( pAig, pDc, pLc );        /* AND */
            case 0x7: return Aig_Not( Aig_And( pAig, pDc, pLc ) ); /* NAND */
            case 0xE: return Aig_Or( pAig, pDc, pLc );         /* OR */
            case 0x1: return Aig_Not( Aig_Or( pAig, pDc, pLc ) );  /* NOR */
            case 0x6: /* XOR */
                return Aig_Or( pAig,
                           Aig_And( pAig, Aig_Not(pDc), pLc ),
                           Aig_And( pAig, pDc, Aig_Not(pLc) ) );
            default: return NULL;
            }
        }

    default: return NULL;
    }
}

/* ---- Main entry point ---- */

int Phy_ResubRun(
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
    int i, nLeaves, nMffc, nNodesBefore, nWords;
    int nAccept = 0, nScanned = 0, nSkipped = 0;
    int nPathPicked[5] = {0, 0, 0, 0, 0};
    int nDivAccept = 0; /* divisor-based acceptances */
    unsigned * pTruth;
    /* temp buffer for truth table operations */
    unsigned  pTempBuf[ 3 * 4 ]; /* up to 3*4=12 words for nVars<=5 */

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

    vTruthElem  = Vec_PtrAllocTruthTables( 5 );
    vTruthStore = Vec_PtrAllocSimInfo( 1024, Kit_TruthWordNum( 5 ) );
    vMemory     = Vec_IntAlloc( 1 << 18 );
    vSupp       = Vec_PtrAlloc( 32 );
    vNodesInt   = Vec_PtrAlloc( 256 );

    Aig_ManForEachNodeReverse( pAig, pObj, i )
    {
        Phy_ResubCand_t cand;
        Aig_Obj_t ** ppFanins;
        Aig_Obj_t ** ppDivObjs;
        Aig_Obj_t * pNewRoot;
        Aig_Obj_t * pIntNode;
        unsigned ** ppDivTruths;
        unsigned ** ppLeafTTs;
        int k, nDivs;

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

        nWords = Kit_TruthWordNum( nLeaves );
        nDivs  = Vec_PtrSize( vNodesInt );

        /* Extract divisor truth tables (already stored in pData by Aig_ManCutTruth) */
        ppDivTruths = (unsigned **)alloca( nDivs * sizeof(unsigned *) );
        ppDivObjs   = (Aig_Obj_t **)alloca( nDivs * sizeof(Aig_Obj_t *) );
        Vec_PtrForEachEntry( Aig_Obj_t *, vNodesInt, pIntNode, k )
        {
            ppDivObjs[k]   = pIntNode;
            ppDivTruths[k] = (unsigned *)pIntNode->pData;
        }

        /* Extract leaf truth tables (elementary vars stored in vTruthElem) */
        ppLeafTTs = (unsigned **)alloca( nLeaves * sizeof(unsigned *) );
        for ( k = 0; k < nLeaves; k++ )
            ppLeafTTs[k] = (unsigned *)Vec_PtrEntry( vTruthElem, k );

        assert( nWords <= 12 );

        /* Evaluate all paths */
        memset( &cand, 0, sizeof(cand) );
        if ( !Phy_ResubEvaluate( pTruth, nLeaves, nMffc,
                                  ppDivTruths, nDivs,
                                  ppLeafTTs,
                                  pTempBuf, nWords,
                                  &cand, vMemory ) )
            continue;

        /* Area improvement threshold: require meaningful cost reduction
           to prevent cumulative bloat from marginal "improvements".
           HIGH is skipped entirely; MID needs stronger justification. */
        {
            float oldCost = Phy_RewriteEstAigCost( nMffc );
            if ( cand.bestPath == PHY_RESUB_PATH_DIV )
                oldCost = Phy_RewriteEstAigCost( nMffc > 1 ? nMffc - 1 : 1 );
            float imprPct = (oldCost - cand.bestCost) / (oldCost + 1e-12f);
            float minImpr = (Part == 2) ? 0.08f : 0.03f;  /* 2=MID */
            if ( imprPct < minImpr )
                continue;
        }

        /* Structure size guard */
        if ( cand.bestPath == PHY_RESUB_PATH_ISOP )
        {
            int RetValue = Kit_TruthIsop( pTruth, nLeaves, vMemory, 1 );
            if ( RetValue == -1 ) continue;
            Kit_Graph_t * pGraph = Kit_SopFactor( vMemory, RetValue, nLeaves, vMemory );
            if ( pGraph == NULL ) continue;
            int nGraphNodes = Kit_GraphNodeNum( pGraph );
            Kit_GraphFree( pGraph );
            if ( nGraphNodes > nMffc + 2 ) continue;
        }
        else if ( cand.bestPath == PHY_RESUB_PATH_DIV )
        {
            /* divisor-based: cost is already computed; no structure explosion risk */
        }
        else
        {
            Kit_DsdNtk_t * pNtk = Kit_DsdDecompose( pTruth, nLeaves );
            if ( pNtk == NULL ) continue;
            Kit_DsdNtk_t * pExp = Kit_DsdExpand( pNtk );
            Kit_DsdNtkFree( pNtk );
            if ( pExp == NULL ) continue;
            int nGraphNodes = Kit_DsdCountAigNodes( pExp );
            Kit_DsdNtkFree( pExp );
            if ( nGraphNodes > nMffc + 2 ) continue;
        }

        nPathPicked[ cand.bestPath ]++;
        if ( cand.bestPath == PHY_RESUB_PATH_DIV ) nDivAccept++;

        /* Build and replace */
        ppFanins = (Aig_Obj_t **)Vec_PtrArray( vSupp );
        pNewRoot = Phy_ResubBuildCandidate( pAig, ppFanins, pTruth, nLeaves,
                                             ppDivObjs, &cand, vMemory );
        if ( pNewRoot == NULL ) continue;
        if ( pNewRoot == pObj || Aig_Regular(pNewRoot) == pObj ) continue;

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

    printf( "phy_resub: scanned=%d skipped=%d accepted=%d (div=%d) nNodes=%d base=%.3f\n",
        nScanned, nSkipped, nAccept, nDivAccept, nNodesBefore, Phy_BaseArea );
    printf( "  paths: ISOP=%d DSD=%d cof=%d DIV=%d\n",
        nPathPicked[PHY_RESUB_PATH_ISOP],
        nPathPicked[PHY_RESUB_PATH_DSD],
        nPathPicked[PHY_RESUB_PATH_COF],
        nPathPicked[PHY_RESUB_PATH_DIV] );

    Vec_PtrFree( vSupp );
    Vec_PtrFree( vNodesInt );
    Vec_PtrFree( vTruthElem );
    Vec_PtrFree( vTruthStore );
    Vec_IntFree( vMemory );

    return nAccept;
}

ABC_NAMESPACE_IMPL_END
