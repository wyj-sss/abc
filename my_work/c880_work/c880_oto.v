// Benchmark "c880_work/c880" written by ABC on Fri Mar 20 09:26:38 2026

module \c880_work/c880  ( 
    G8, G16, G6, G17, G7, G18, G19, G4, G3, G2, G1, G5, G11, G23, G20, G21,
    G9, G10, G12, G15, G22, G32, G24, G25, G26, G27, G28, G29, G30, G31,
    G33, G41, G42, G43, G44, G45, G46, G47, G48, G49, G13, G14, G55, G59,
    G54, G60, G39, G40, G52, G53, G50, G51, G58, G35, G37, G36, G56, G57,
    G34, G38,
    G855, G856, G857, G858, G859, G860, G861, G862, G863, G864, G865, G866,
    G867, G868, G869, G870, G871, G872, G873, G874, G875, G876, G877, G878,
    G879, G880  );
  input  G8, G16, G6, G17, G7, G18, G19, G4, G3, G2, G1, G5, G11, G23,
    G20, G21, G9, G10, G12, G15, G22, G32, G24, G25, G26, G27, G28, G29,
    G30, G31, G33, G41, G42, G43, G44, G45, G46, G47, G48, G49, G13, G14,
    G55, G59, G54, G60, G39, G40, G52, G53, G50, G51, G58, G35, G37, G36,
    G56, G57, G34, G38;
  output G855, G856, G857, G858, G859, G860, G861, G862, G863, G864, G865,
    G866, G867, G868, G869, G870, G871, G872, G873, G874, G875, G876, G877,
    G878, G879, G880;
  wire new_n87, new_n91, new_n96, new_n99, new_n101, new_n105, new_n107,
    new_n111, new_n115, new_n121, new_n122, new_n123, new_n130, new_n131,
    new_n133, new_n135, new_n139, new_n141, new_n147, new_n149, new_n150,
    new_n151, new_n153, new_n154, new_n155, new_n157, new_n158, new_n159,
    new_n161, new_n162, new_n163, new_n165, new_n167, new_n168, new_n169,
    new_n171, new_n172, new_n174, new_n175, new_n176, new_n178, new_n179,
    new_n180, new_n182, new_n183, new_n184, new_n186, new_n187, new_n188,
    new_n190, new_n191, new_n192, new_n194, new_n196, new_n197, new_n198,
    new_n200, new_n201, new_n203, new_n204, new_n205, new_n207, new_n211,
    new_n213, new_n214, new_n215, new_n217, new_n218, new_n219, new_n221,
    new_n222, new_n223, new_n225, new_n226, new_n227, new_n229, new_n231,
    new_n232, new_n233, new_n235, new_n237, new_n238, new_n239, new_n241,
    new_n242, new_n243, new_n245, new_n246, new_n247, new_n249, new_n250,
    new_n251, new_n253, new_n254, new_n255, new_n257, new_n259, new_n260,
    new_n261, new_n263, new_n264, new_n266, new_n267, new_n268, new_n270,
    new_n274, new_n276, new_n278, new_n280, new_n282, new_n284, new_n286,
    new_n288, new_n290, new_n292, new_n294, new_n295, new_n297, new_n299,
    new_n301, new_n303, new_n305, new_n307, new_n309, new_n310, new_n311,
    new_n313, new_n315, new_n317, new_n319, new_n321, new_n323, new_n325,
    new_n327, new_n329, new_n331, new_n333, new_n335, new_n336, new_n337,
    new_n339, new_n341, new_n343, new_n345, new_n346, new_n347, new_n348,
    new_n349, new_n351, new_n353, new_n355, new_n357, new_n358, new_n360,
    new_n362, new_n364, new_n366, new_n368, new_n372, new_n374, new_n376,
    new_n378, new_n379, new_n380, new_n382, new_n384, new_n386, new_n388,
    new_n389, new_n390, new_n391, new_n392, new_n394, new_n396, new_n398,
    new_n400, new_n401, new_n402, new_n404, new_n406, new_n408, new_n409,
    new_n410, new_n412, new_n414, new_n416, new_n418, new_n419, new_n420,
    new_n422, new_n424, new_n426, new_n428, new_n430, new_n431, new_n432,
    new_n434, new_n435, new_n436, new_n438, new_n439, new_n440, new_n442,
    new_n444, new_n446, new_n448, new_n450, new_n454, new_n456, new_n458,
    new_n460, new_n462, new_n464, new_n465, new_n466, new_n468, new_n470,
    new_n472, new_n474, new_n476, new_n478, new_n480, new_n482, new_n483,
    new_n484, new_n486, new_n488, new_n490, new_n492, new_n494, new_n498,
    new_n500, new_n502, new_n504, new_n506, new_n508, new_n509, new_n510,
    new_n512, new_n514, new_n516, new_n518, new_n519, new_n520, new_n522,
    new_n524, new_n526, new_n528, new_n530, new_n534, new_n536, new_n538,
    new_n540, new_n542, new_n544, new_n546, new_n548, new_n550, new_n552,
    new_n553, new_n554, new_n555, new_n556, new_n558, new_n559, new_n560,
    new_n562, new_n564, new_n566, new_n568, new_n570, new_n571, new_n572,
    new_n574, new_n575, new_n576, new_n578, new_n580, new_n582, new_n584,
    new_n586, new_n587, new_n588, new_n590, new_n592, new_n594, new_n596,
    new_n598, new_n600, new_n601, new_n602, new_n604, new_n606, new_n608,
    new_n609, new_n610, new_n612, new_n614, new_n615, new_n616, new_n618,
    new_n619, new_n620, new_n622, new_n623, new_n624, new_n626, new_n630,
    new_n632, new_n634, new_n636, new_n637, new_n638, new_n640, new_n642,
    new_n644, new_n646, new_n648, new_n650, new_n652, new_n654, new_n656,
    new_n660, new_n662, new_n664, new_n666, new_n667, new_n668, new_n670,
    new_n672, new_n674, new_n676, new_n678, new_n680, new_n682, new_n684,
    new_n686, new_n690, new_n692, new_n694, new_n696, new_n697, new_n698,
    new_n700, new_n702, new_n704, new_n706, new_n708, new_n710, new_n712,
    new_n714, new_n715, new_n716, new_n718, new_n720, new_n722, new_n724,
    new_n726, new_n730, new_n732, new_n734, new_n736, new_n737, new_n738,
    new_n740, new_n742, new_n744, new_n746, new_n747, new_n748, new_n750,
    new_n752, new_n754, new_n756, new_n758;
  AND2_X1   g000(.A1(G16), .A2(G6), .ZN(new_n87));
  NAND2_X1  g001(.A1(G8), .A2(new_n87), .ZN(G855));
  AND2_X1   g002(.A1(G6), .A2(G7), .ZN(new_n91));
  NAND2_X1  g003(.A1(G17), .A2(new_n91), .ZN(G856));
  NAND2_X1  g004(.A1(G8), .A2(new_n91), .ZN(G857));
  INV_X1    g005(.A(G857), .ZN(new_n96));
  NAND2_X1  g006(.A1(G18), .A2(G19), .ZN(G858));
  AND2_X1   g007(.A1(G4), .A2(G3), .ZN(new_n99));
  AND2_X1   g008(.A1(G2), .A2(G1), .ZN(new_n101));
  NAND2_X1  g009(.A1(new_n99), .A2(new_n101), .ZN(G859));
  AND2_X1   g010(.A1(G1), .A2(G5), .ZN(new_n105));
  AND2_X1   g011(.A1(new_n99), .A2(new_n105), .ZN(new_n107));
  AND2_X1   g012(.A1(G857), .A2(new_n107), .ZN(G860));
  AND2_X1   g013(.A1(G16), .A2(G11), .ZN(new_n111));
  AND2_X1   g014(.A1(G17), .A2(new_n111), .ZN(G861));
  AND2_X1   g015(.A1(G7), .A2(G11), .ZN(new_n115));
  AND2_X1   g016(.A1(G17), .A2(new_n115), .ZN(G862));
  AND2_X1   g017(.A1(G8), .A2(new_n115), .ZN(G863));
  INV_X1    g018(.A(G20), .ZN(new_n121));
  INV_X1    g019(.A(G21), .ZN(new_n122));
  NAND2_X1  g020(.A1(new_n121), .A2(new_n122), .ZN(new_n123));
  NAND2_X1  g021(.A1(G23), .A2(new_n123), .ZN(G864));
  AND2_X1   g022(.A1(new_n96), .A2(new_n107), .ZN(G865));
  NAND2_X1  g023(.A1(G9), .A2(new_n105), .ZN(G866));
  INV_X1    g024(.A(G866), .ZN(new_n130));
  AND2_X1   g025(.A1(G3), .A2(G10), .ZN(new_n131));
  AND2_X1   g026(.A1(new_n101), .A2(new_n131), .ZN(new_n133));
  AND2_X1   g027(.A1(G6), .A2(G12), .ZN(new_n135));
  NAND2_X1  g028(.A1(new_n133), .A2(new_n135), .ZN(G867));
  AND2_X1   g029(.A1(G11), .A2(G12), .ZN(new_n139));
  AND2_X1   g030(.A1(G15), .A2(new_n139), .ZN(new_n141));
  NAND2_X1  g031(.A1(new_n133), .A2(new_n141), .ZN(G868));
  NAND2_X1  g032(.A1(G22), .A2(new_n123), .ZN(G869));
  NAND2_X1  g033(.A1(G24), .A2(G25), .ZN(new_n147));
  INV_X1    g034(.A(G24), .ZN(new_n149));
  INV_X1    g035(.A(G25), .ZN(new_n150));
  NAND2_X1  g036(.A1(new_n149), .A2(new_n150), .ZN(new_n151));
  NAND2_X1  g037(.A1(new_n147), .A2(new_n151), .ZN(new_n153));
  INV_X1    g038(.A(new_n153), .ZN(new_n154));
  NAND2_X1  g039(.A1(G26), .A2(G27), .ZN(new_n155));
  INV_X1    g040(.A(G26), .ZN(new_n157));
  INV_X1    g041(.A(G27), .ZN(new_n158));
  NAND2_X1  g042(.A1(new_n157), .A2(new_n158), .ZN(new_n159));
  NAND2_X1  g043(.A1(new_n155), .A2(new_n159), .ZN(new_n161));
  INV_X1    g044(.A(new_n161), .ZN(new_n162));
  NAND2_X1  g045(.A1(new_n153), .A2(new_n161), .ZN(new_n163));
  NAND2_X1  g046(.A1(new_n154), .A2(new_n162), .ZN(new_n165));
  NAND2_X1  g047(.A1(new_n163), .A2(new_n165), .ZN(new_n167));
  INV_X1    g048(.A(new_n167), .ZN(new_n168));
  NAND2_X1  g049(.A1(G32), .A2(new_n168), .ZN(new_n169));
  INV_X1    g050(.A(G32), .ZN(new_n171));
  NAND2_X1  g051(.A1(new_n171), .A2(new_n167), .ZN(new_n172));
  NAND2_X1  g052(.A1(new_n169), .A2(new_n172), .ZN(new_n174));
  INV_X1    g053(.A(new_n174), .ZN(new_n175));
  NAND2_X1  g054(.A1(G28), .A2(G29), .ZN(new_n176));
  INV_X1    g055(.A(G28), .ZN(new_n178));
  INV_X1    g056(.A(G29), .ZN(new_n179));
  NAND2_X1  g057(.A1(new_n178), .A2(new_n179), .ZN(new_n180));
  NAND2_X1  g058(.A1(new_n176), .A2(new_n180), .ZN(new_n182));
  INV_X1    g059(.A(new_n182), .ZN(new_n183));
  NAND2_X1  g060(.A1(G30), .A2(G31), .ZN(new_n184));
  INV_X1    g061(.A(G30), .ZN(new_n186));
  INV_X1    g062(.A(G31), .ZN(new_n187));
  NAND2_X1  g063(.A1(new_n186), .A2(new_n187), .ZN(new_n188));
  NAND2_X1  g064(.A1(new_n184), .A2(new_n188), .ZN(new_n190));
  INV_X1    g065(.A(new_n190), .ZN(new_n191));
  NAND2_X1  g066(.A1(new_n182), .A2(new_n190), .ZN(new_n192));
  NAND2_X1  g067(.A1(new_n183), .A2(new_n191), .ZN(new_n194));
  NAND2_X1  g068(.A1(new_n192), .A2(new_n194), .ZN(new_n196));
  INV_X1    g069(.A(new_n196), .ZN(new_n197));
  NAND2_X1  g070(.A1(G33), .A2(new_n197), .ZN(new_n198));
  INV_X1    g071(.A(G33), .ZN(new_n200));
  NAND2_X1  g072(.A1(new_n200), .A2(new_n196), .ZN(new_n201));
  NAND2_X1  g073(.A1(new_n198), .A2(new_n201), .ZN(new_n203));
  INV_X1    g074(.A(new_n203), .ZN(new_n204));
  NAND2_X1  g075(.A1(new_n174), .A2(new_n203), .ZN(new_n205));
  NAND2_X1  g076(.A1(new_n175), .A2(new_n204), .ZN(new_n207));
  NAND2_X1  g077(.A1(new_n205), .A2(new_n207), .ZN(G870));
  NAND2_X1  g078(.A1(G41), .A2(G42), .ZN(new_n211));
  INV_X1    g079(.A(G41), .ZN(new_n213));
  INV_X1    g080(.A(G42), .ZN(new_n214));
  NAND2_X1  g081(.A1(new_n213), .A2(new_n214), .ZN(new_n215));
  NAND2_X1  g082(.A1(new_n211), .A2(new_n215), .ZN(new_n217));
  INV_X1    g083(.A(new_n217), .ZN(new_n218));
  NAND2_X1  g084(.A1(G43), .A2(G44), .ZN(new_n219));
  INV_X1    g085(.A(G43), .ZN(new_n221));
  INV_X1    g086(.A(G44), .ZN(new_n222));
  NAND2_X1  g087(.A1(new_n221), .A2(new_n222), .ZN(new_n223));
  NAND2_X1  g088(.A1(new_n219), .A2(new_n223), .ZN(new_n225));
  INV_X1    g089(.A(new_n225), .ZN(new_n226));
  NAND2_X1  g090(.A1(new_n217), .A2(new_n225), .ZN(new_n227));
  NAND2_X1  g091(.A1(new_n218), .A2(new_n226), .ZN(new_n229));
  NAND2_X1  g092(.A1(new_n227), .A2(new_n229), .ZN(new_n231));
  INV_X1    g093(.A(new_n231), .ZN(new_n232));
  NAND2_X1  g094(.A1(G32), .A2(new_n232), .ZN(new_n233));
  NAND2_X1  g095(.A1(new_n171), .A2(new_n231), .ZN(new_n235));
  NAND2_X1  g096(.A1(new_n233), .A2(new_n235), .ZN(new_n237));
  INV_X1    g097(.A(new_n237), .ZN(new_n238));
  NAND2_X1  g098(.A1(G45), .A2(G46), .ZN(new_n239));
  INV_X1    g099(.A(G45), .ZN(new_n241));
  INV_X1    g100(.A(G46), .ZN(new_n242));
  NAND2_X1  g101(.A1(new_n241), .A2(new_n242), .ZN(new_n243));
  NAND2_X1  g102(.A1(new_n239), .A2(new_n243), .ZN(new_n245));
  INV_X1    g103(.A(new_n245), .ZN(new_n246));
  NAND2_X1  g104(.A1(G47), .A2(G48), .ZN(new_n247));
  INV_X1    g105(.A(G47), .ZN(new_n249));
  INV_X1    g106(.A(G48), .ZN(new_n250));
  NAND2_X1  g107(.A1(new_n249), .A2(new_n250), .ZN(new_n251));
  NAND2_X1  g108(.A1(new_n247), .A2(new_n251), .ZN(new_n253));
  INV_X1    g109(.A(new_n253), .ZN(new_n254));
  NAND2_X1  g110(.A1(new_n245), .A2(new_n253), .ZN(new_n255));
  NAND2_X1  g111(.A1(new_n246), .A2(new_n254), .ZN(new_n257));
  NAND2_X1  g112(.A1(new_n255), .A2(new_n257), .ZN(new_n259));
  INV_X1    g113(.A(new_n259), .ZN(new_n260));
  NAND2_X1  g114(.A1(G49), .A2(new_n260), .ZN(new_n261));
  INV_X1    g115(.A(G49), .ZN(new_n263));
  NAND2_X1  g116(.A1(new_n263), .A2(new_n259), .ZN(new_n264));
  NAND2_X1  g117(.A1(new_n261), .A2(new_n264), .ZN(new_n266));
  INV_X1    g118(.A(new_n266), .ZN(new_n267));
  NAND2_X1  g119(.A1(new_n237), .A2(new_n266), .ZN(new_n268));
  NAND2_X1  g120(.A1(new_n238), .A2(new_n267), .ZN(new_n270));
  NAND2_X1  g121(.A1(new_n268), .A2(new_n270), .ZN(G871));
  AND2_X1   g122(.A1(G12), .A2(G13), .ZN(new_n274));
  AND2_X1   g123(.A1(G8), .A2(G11), .ZN(new_n276));
  AND2_X1   g124(.A1(new_n274), .A2(new_n276), .ZN(new_n278));
  AND2_X1   g125(.A1(new_n133), .A2(new_n278), .ZN(new_n280));
  AND2_X1   g126(.A1(G14), .A2(new_n280), .ZN(new_n282));
  NAND2_X1  g127(.A1(G48), .A2(new_n282), .ZN(new_n284));
  NAND2_X1  g128(.A1(G55), .A2(G59), .ZN(new_n286));
  AND2_X1   g129(.A1(G17), .A2(new_n87), .ZN(new_n288));
  AND2_X1   g130(.A1(new_n130), .A2(new_n288), .ZN(new_n290));
  AND2_X1   g131(.A1(G10), .A2(new_n290), .ZN(new_n292));
  INV_X1    g132(.A(G60), .ZN(new_n294));
  NAND2_X1  g133(.A1(new_n294), .A2(new_n292), .ZN(new_n295));
  NAND2_X1  g134(.A1(G11), .A2(G40), .ZN(new_n297));
  AND2_X1   g135(.A1(new_n130), .A2(new_n297), .ZN(new_n299));
  NAND2_X1  g136(.A1(G4), .A2(new_n299), .ZN(new_n301));
  NAND2_X1  g137(.A1(G1), .A2(new_n301), .ZN(new_n303));
  NAND2_X1  g138(.A1(G39), .A2(new_n303), .ZN(new_n305));
  AND2_X1   g139(.A1(G40), .A2(new_n130), .ZN(new_n307));
  INV_X1    g140(.A(G8), .ZN(new_n309));
  INV_X1    g141(.A(G4), .ZN(new_n310));
  NAND2_X1  g142(.A1(new_n309), .A2(new_n310), .ZN(new_n311));
  NAND2_X1  g143(.A1(G8), .A2(G4), .ZN(new_n313));
  AND2_X1   g144(.A1(new_n311), .A2(new_n313), .ZN(new_n315));
  AND2_X1   g145(.A1(G11), .A2(new_n315), .ZN(new_n317));
  NAND2_X1  g146(.A1(new_n307), .A2(new_n317), .ZN(new_n319));
  AND2_X1   g147(.A1(G4), .A2(G9), .ZN(new_n321));
  AND2_X1   g148(.A1(new_n101), .A2(new_n321), .ZN(new_n323));
  NAND2_X1  g149(.A1(G8), .A2(new_n111), .ZN(new_n325));
  NAND2_X1  g150(.A1(new_n323), .A2(new_n325), .ZN(new_n327));
  NAND2_X1  g151(.A1(new_n319), .A2(new_n327), .ZN(new_n329));
  NAND2_X1  g152(.A1(G31), .A2(new_n329), .ZN(new_n331));
  AND2_X1   g153(.A1(new_n305), .A2(new_n331), .ZN(new_n333));
  NAND2_X1  g154(.A1(new_n295), .A2(new_n333), .ZN(new_n335));
  INV_X1    g155(.A(new_n335), .ZN(new_n336));
  NAND2_X1  g156(.A1(G54), .A2(new_n335), .ZN(new_n337));
  AND2_X1   g157(.A1(new_n286), .A2(new_n337), .ZN(new_n339));
  AND2_X1   g158(.A1(new_n284), .A2(new_n339), .ZN(new_n341));
  NAND2_X1  g159(.A1(new_n250), .A2(new_n336), .ZN(new_n343));
  NAND2_X1  g160(.A1(G48), .A2(new_n335), .ZN(new_n345));
  INV_X1    g161(.A(new_n345), .ZN(new_n346));
  NAND2_X1  g162(.A1(new_n343), .A2(new_n345), .ZN(new_n347));
  INV_X1    g163(.A(new_n347), .ZN(new_n348));
  NAND2_X1  g164(.A1(G52), .A2(new_n348), .ZN(new_n349));
  NAND2_X1  g165(.A1(G53), .A2(new_n346), .ZN(new_n351));
  AND2_X1   g166(.A1(new_n349), .A2(new_n351), .ZN(new_n353));
  NAND2_X1  g167(.A1(G30), .A2(G50), .ZN(new_n355));
  INV_X1    g168(.A(G58), .ZN(new_n357));
  NAND2_X1  g169(.A1(new_n357), .A2(new_n347), .ZN(new_n358));
  NAND2_X1  g170(.A1(G58), .A2(new_n348), .ZN(new_n360));
  AND2_X1   g171(.A1(new_n358), .A2(new_n360), .ZN(new_n362));
  NAND2_X1  g172(.A1(G51), .A2(new_n362), .ZN(new_n364));
  AND2_X1   g173(.A1(new_n355), .A2(new_n364), .ZN(new_n366));
  AND2_X1   g174(.A1(new_n353), .A2(new_n366), .ZN(new_n368));
  AND2_X1   g175(.A1(new_n341), .A2(new_n368), .ZN(G872));
  NAND2_X1  g176(.A1(G35), .A2(new_n303), .ZN(new_n372));
  NAND2_X1  g177(.A1(G28), .A2(new_n329), .ZN(new_n374));
  AND2_X1   g178(.A1(new_n372), .A2(new_n374), .ZN(new_n376));
  NAND2_X1  g179(.A1(new_n295), .A2(new_n376), .ZN(new_n378));
  INV_X1    g180(.A(new_n378), .ZN(new_n379));
  NAND2_X1  g181(.A1(G54), .A2(new_n378), .ZN(new_n380));
  NAND2_X1  g182(.A1(G45), .A2(new_n282), .ZN(new_n382));
  AND2_X1   g183(.A1(new_n380), .A2(new_n382), .ZN(new_n384));
  NAND2_X1  g184(.A1(new_n241), .A2(new_n379), .ZN(new_n386));
  NAND2_X1  g185(.A1(G45), .A2(new_n378), .ZN(new_n388));
  INV_X1    g186(.A(new_n388), .ZN(new_n389));
  NAND2_X1  g187(.A1(new_n386), .A2(new_n388), .ZN(new_n390));
  INV_X1    g188(.A(new_n390), .ZN(new_n391));
  NAND2_X1  g189(.A1(G52), .A2(new_n391), .ZN(new_n392));
  NAND2_X1  g190(.A1(G53), .A2(new_n389), .ZN(new_n394));
  AND2_X1   g191(.A1(new_n392), .A2(new_n394), .ZN(new_n396));
  NAND2_X1  g192(.A1(G27), .A2(G50), .ZN(new_n398));
  NAND2_X1  g193(.A1(G58), .A2(new_n343), .ZN(new_n400));
  INV_X1    g194(.A(new_n400), .ZN(new_n401));
  NAND2_X1  g195(.A1(G37), .A2(new_n303), .ZN(new_n402));
  NAND2_X1  g196(.A1(G30), .A2(new_n329), .ZN(new_n404));
  AND2_X1   g197(.A1(new_n402), .A2(new_n404), .ZN(new_n406));
  NAND2_X1  g198(.A1(new_n295), .A2(new_n406), .ZN(new_n408));
  INV_X1    g199(.A(new_n408), .ZN(new_n409));
  NAND2_X1  g200(.A1(new_n249), .A2(new_n409), .ZN(new_n410));
  NAND2_X1  g201(.A1(G36), .A2(new_n303), .ZN(new_n412));
  NAND2_X1  g202(.A1(G29), .A2(new_n329), .ZN(new_n414));
  AND2_X1   g203(.A1(new_n412), .A2(new_n414), .ZN(new_n416));
  NAND2_X1  g204(.A1(new_n295), .A2(new_n416), .ZN(new_n418));
  INV_X1    g205(.A(new_n418), .ZN(new_n419));
  NAND2_X1  g206(.A1(new_n242), .A2(new_n419), .ZN(new_n420));
  AND2_X1   g207(.A1(new_n410), .A2(new_n420), .ZN(new_n422));
  NAND2_X1  g208(.A1(new_n401), .A2(new_n422), .ZN(new_n424));
  NAND2_X1  g209(.A1(new_n346), .A2(new_n422), .ZN(new_n426));
  AND2_X1   g210(.A1(new_n424), .A2(new_n426), .ZN(new_n428));
  NAND2_X1  g211(.A1(G47), .A2(new_n408), .ZN(new_n430));
  INV_X1    g212(.A(new_n430), .ZN(new_n431));
  NAND2_X1  g213(.A1(new_n420), .A2(new_n431), .ZN(new_n432));
  NAND2_X1  g214(.A1(G46), .A2(new_n418), .ZN(new_n434));
  INV_X1    g215(.A(new_n434), .ZN(new_n435));
  AND2_X1   g216(.A1(new_n432), .A2(new_n434), .ZN(new_n436));
  NAND2_X1  g217(.A1(new_n428), .A2(new_n436), .ZN(new_n438));
  INV_X1    g218(.A(new_n438), .ZN(new_n439));
  NAND2_X1  g219(.A1(new_n390), .A2(new_n439), .ZN(new_n440));
  NAND2_X1  g220(.A1(new_n391), .A2(new_n438), .ZN(new_n442));
  AND2_X1   g221(.A1(new_n440), .A2(new_n442), .ZN(new_n444));
  NAND2_X1  g222(.A1(G51), .A2(new_n444), .ZN(new_n446));
  AND2_X1   g223(.A1(new_n398), .A2(new_n446), .ZN(new_n448));
  AND2_X1   g224(.A1(new_n396), .A2(new_n448), .ZN(new_n450));
  AND2_X1   g225(.A1(new_n384), .A2(new_n450), .ZN(G873));
  NAND2_X1  g226(.A1(G46), .A2(new_n282), .ZN(new_n454));
  NAND2_X1  g227(.A1(G55), .A2(G56), .ZN(new_n456));
  NAND2_X1  g228(.A1(G54), .A2(new_n418), .ZN(new_n458));
  AND2_X1   g229(.A1(new_n456), .A2(new_n458), .ZN(new_n460));
  AND2_X1   g230(.A1(new_n454), .A2(new_n460), .ZN(new_n462));
  NAND2_X1  g231(.A1(new_n420), .A2(new_n434), .ZN(new_n464));
  INV_X1    g232(.A(new_n464), .ZN(new_n465));
  NAND2_X1  g233(.A1(G52), .A2(new_n465), .ZN(new_n466));
  NAND2_X1  g234(.A1(G53), .A2(new_n435), .ZN(new_n468));
  AND2_X1   g235(.A1(new_n466), .A2(new_n468), .ZN(new_n470));
  NAND2_X1  g236(.A1(G28), .A2(G50), .ZN(new_n472));
  AND2_X1   g237(.A1(new_n343), .A2(new_n410), .ZN(new_n474));
  NAND2_X1  g238(.A1(G58), .A2(new_n474), .ZN(new_n476));
  NAND2_X1  g239(.A1(new_n346), .A2(new_n410), .ZN(new_n478));
  AND2_X1   g240(.A1(new_n430), .A2(new_n478), .ZN(new_n480));
  NAND2_X1  g241(.A1(new_n476), .A2(new_n480), .ZN(new_n482));
  INV_X1    g242(.A(new_n482), .ZN(new_n483));
  NAND2_X1  g243(.A1(new_n464), .A2(new_n483), .ZN(new_n484));
  NAND2_X1  g244(.A1(new_n465), .A2(new_n482), .ZN(new_n486));
  AND2_X1   g245(.A1(new_n484), .A2(new_n486), .ZN(new_n488));
  NAND2_X1  g246(.A1(G51), .A2(new_n488), .ZN(new_n490));
  AND2_X1   g247(.A1(new_n472), .A2(new_n490), .ZN(new_n492));
  AND2_X1   g248(.A1(new_n470), .A2(new_n492), .ZN(new_n494));
  AND2_X1   g249(.A1(new_n462), .A2(new_n494), .ZN(G874));
  NAND2_X1  g250(.A1(G47), .A2(new_n282), .ZN(new_n498));
  NAND2_X1  g251(.A1(G55), .A2(G57), .ZN(new_n500));
  NAND2_X1  g252(.A1(G54), .A2(new_n408), .ZN(new_n502));
  AND2_X1   g253(.A1(new_n500), .A2(new_n502), .ZN(new_n504));
  AND2_X1   g254(.A1(new_n498), .A2(new_n504), .ZN(new_n506));
  NAND2_X1  g255(.A1(new_n410), .A2(new_n430), .ZN(new_n508));
  INV_X1    g256(.A(new_n508), .ZN(new_n509));
  NAND2_X1  g257(.A1(G52), .A2(new_n509), .ZN(new_n510));
  NAND2_X1  g258(.A1(G53), .A2(new_n431), .ZN(new_n512));
  AND2_X1   g259(.A1(new_n510), .A2(new_n512), .ZN(new_n514));
  NAND2_X1  g260(.A1(G29), .A2(G50), .ZN(new_n516));
  NAND2_X1  g261(.A1(new_n345), .A2(new_n400), .ZN(new_n518));
  INV_X1    g262(.A(new_n518), .ZN(new_n519));
  NAND2_X1  g263(.A1(new_n508), .A2(new_n519), .ZN(new_n520));
  NAND2_X1  g264(.A1(new_n509), .A2(new_n518), .ZN(new_n522));
  AND2_X1   g265(.A1(new_n520), .A2(new_n522), .ZN(new_n524));
  NAND2_X1  g266(.A1(G51), .A2(new_n524), .ZN(new_n526));
  AND2_X1   g267(.A1(new_n516), .A2(new_n526), .ZN(new_n528));
  AND2_X1   g268(.A1(new_n514), .A2(new_n528), .ZN(new_n530));
  AND2_X1   g269(.A1(new_n506), .A2(new_n530), .ZN(G875));
  NAND2_X1  g270(.A1(G2), .A2(G34), .ZN(new_n534));
  NAND2_X1  g271(.A1(G24), .A2(new_n329), .ZN(new_n536));
  AND2_X1   g272(.A1(new_n534), .A2(new_n536), .ZN(new_n538));
  AND2_X1   g273(.A1(G10), .A2(new_n299), .ZN(new_n540));
  NAND2_X1  g274(.A1(G35), .A2(new_n540), .ZN(new_n542));
  AND2_X1   g275(.A1(G4), .A2(new_n130), .ZN(new_n544));
  AND2_X1   g276(.A1(new_n288), .A2(new_n544), .ZN(new_n546));
  NAND2_X1  g277(.A1(new_n294), .A2(new_n546), .ZN(new_n548));
  AND2_X1   g278(.A1(new_n542), .A2(new_n548), .ZN(new_n550));
  NAND2_X1  g279(.A1(new_n538), .A2(new_n550), .ZN(new_n552));
  INV_X1    g280(.A(new_n552), .ZN(new_n553));
  NAND2_X1  g281(.A1(G41), .A2(new_n552), .ZN(new_n554));
  INV_X1    g282(.A(new_n554), .ZN(new_n555));
  NAND2_X1  g283(.A1(new_n386), .A2(new_n438), .ZN(new_n556));
  NAND2_X1  g284(.A1(new_n388), .A2(new_n556), .ZN(new_n558));
  INV_X1    g285(.A(new_n558), .ZN(new_n559));
  NAND2_X1  g286(.A1(G34), .A2(G38), .ZN(new_n560));
  NAND2_X1  g287(.A1(G27), .A2(new_n329), .ZN(new_n562));
  AND2_X1   g288(.A1(new_n560), .A2(new_n562), .ZN(new_n564));
  NAND2_X1  g289(.A1(G39), .A2(new_n540), .ZN(new_n566));
  AND2_X1   g290(.A1(new_n548), .A2(new_n566), .ZN(new_n568));
  NAND2_X1  g291(.A1(new_n564), .A2(new_n568), .ZN(new_n570));
  INV_X1    g292(.A(new_n570), .ZN(new_n571));
  NAND2_X1  g293(.A1(new_n222), .A2(new_n571), .ZN(new_n572));
  NAND2_X1  g294(.A1(new_n558), .A2(new_n572), .ZN(new_n574));
  INV_X1    g295(.A(new_n574), .ZN(new_n575));
  NAND2_X1  g296(.A1(G4), .A2(G34), .ZN(new_n576));
  NAND2_X1  g297(.A1(G26), .A2(new_n329), .ZN(new_n578));
  AND2_X1   g298(.A1(new_n576), .A2(new_n578), .ZN(new_n580));
  NAND2_X1  g299(.A1(G37), .A2(new_n540), .ZN(new_n582));
  AND2_X1   g300(.A1(new_n548), .A2(new_n582), .ZN(new_n584));
  NAND2_X1  g301(.A1(new_n580), .A2(new_n584), .ZN(new_n586));
  INV_X1    g302(.A(new_n586), .ZN(new_n587));
  NAND2_X1  g303(.A1(new_n221), .A2(new_n587), .ZN(new_n588));
  NAND2_X1  g304(.A1(G9), .A2(G34), .ZN(new_n590));
  NAND2_X1  g305(.A1(G25), .A2(new_n329), .ZN(new_n592));
  AND2_X1   g306(.A1(new_n590), .A2(new_n592), .ZN(new_n594));
  NAND2_X1  g307(.A1(G36), .A2(new_n540), .ZN(new_n596));
  AND2_X1   g308(.A1(new_n548), .A2(new_n596), .ZN(new_n598));
  NAND2_X1  g309(.A1(new_n594), .A2(new_n598), .ZN(new_n600));
  INV_X1    g310(.A(new_n600), .ZN(new_n601));
  NAND2_X1  g311(.A1(new_n214), .A2(new_n601), .ZN(new_n602));
  AND2_X1   g312(.A1(new_n588), .A2(new_n602), .ZN(new_n604));
  NAND2_X1  g313(.A1(new_n575), .A2(new_n604), .ZN(new_n606));
  NAND2_X1  g314(.A1(G44), .A2(new_n570), .ZN(new_n608));
  INV_X1    g315(.A(new_n608), .ZN(new_n609));
  NAND2_X1  g316(.A1(new_n604), .A2(new_n609), .ZN(new_n610));
  AND2_X1   g317(.A1(new_n606), .A2(new_n610), .ZN(new_n612));
  NAND2_X1  g318(.A1(G43), .A2(new_n586), .ZN(new_n614));
  INV_X1    g319(.A(new_n614), .ZN(new_n615));
  NAND2_X1  g320(.A1(new_n602), .A2(new_n615), .ZN(new_n616));
  NAND2_X1  g321(.A1(G42), .A2(new_n600), .ZN(new_n618));
  INV_X1    g322(.A(new_n618), .ZN(new_n619));
  AND2_X1   g323(.A1(new_n616), .A2(new_n618), .ZN(new_n620));
  NAND2_X1  g324(.A1(new_n612), .A2(new_n620), .ZN(new_n622));
  INV_X1    g325(.A(new_n622), .ZN(new_n623));
  NAND2_X1  g326(.A1(new_n213), .A2(new_n553), .ZN(new_n624));
  NAND2_X1  g327(.A1(new_n622), .A2(new_n624), .ZN(new_n626));
  AND2_X1   g328(.A1(new_n554), .A2(new_n626), .ZN(G876));
  NAND2_X1  g329(.A1(G54), .A2(new_n570), .ZN(new_n630));
  NAND2_X1  g330(.A1(G44), .A2(new_n282), .ZN(new_n632));
  AND2_X1   g331(.A1(new_n630), .A2(new_n632), .ZN(new_n634));
  NAND2_X1  g332(.A1(new_n572), .A2(new_n608), .ZN(new_n636));
  INV_X1    g333(.A(new_n636), .ZN(new_n637));
  NAND2_X1  g334(.A1(G52), .A2(new_n637), .ZN(new_n638));
  NAND2_X1  g335(.A1(G53), .A2(new_n609), .ZN(new_n640));
  AND2_X1   g336(.A1(new_n638), .A2(new_n640), .ZN(new_n642));
  NAND2_X1  g337(.A1(G26), .A2(G50), .ZN(new_n644));
  NAND2_X1  g338(.A1(new_n559), .A2(new_n636), .ZN(new_n646));
  NAND2_X1  g339(.A1(new_n558), .A2(new_n637), .ZN(new_n648));
  AND2_X1   g340(.A1(new_n646), .A2(new_n648), .ZN(new_n650));
  NAND2_X1  g341(.A1(G51), .A2(new_n650), .ZN(new_n652));
  AND2_X1   g342(.A1(new_n644), .A2(new_n652), .ZN(new_n654));
  AND2_X1   g343(.A1(new_n642), .A2(new_n654), .ZN(new_n656));
  AND2_X1   g344(.A1(new_n634), .A2(new_n656), .ZN(G877));
  NAND2_X1  g345(.A1(G54), .A2(new_n552), .ZN(new_n660));
  NAND2_X1  g346(.A1(G41), .A2(new_n282), .ZN(new_n662));
  AND2_X1   g347(.A1(new_n660), .A2(new_n662), .ZN(new_n664));
  NAND2_X1  g348(.A1(new_n554), .A2(new_n624), .ZN(new_n666));
  INV_X1    g349(.A(new_n666), .ZN(new_n667));
  NAND2_X1  g350(.A1(G52), .A2(new_n667), .ZN(new_n668));
  NAND2_X1  g351(.A1(G53), .A2(new_n555), .ZN(new_n670));
  AND2_X1   g352(.A1(new_n668), .A2(new_n670), .ZN(new_n672));
  NAND2_X1  g353(.A1(G60), .A2(G50), .ZN(new_n674));
  NAND2_X1  g354(.A1(new_n623), .A2(new_n666), .ZN(new_n676));
  NAND2_X1  g355(.A1(new_n622), .A2(new_n667), .ZN(new_n678));
  AND2_X1   g356(.A1(new_n676), .A2(new_n678), .ZN(new_n680));
  NAND2_X1  g357(.A1(G51), .A2(new_n680), .ZN(new_n682));
  AND2_X1   g358(.A1(new_n674), .A2(new_n682), .ZN(new_n684));
  AND2_X1   g359(.A1(new_n672), .A2(new_n684), .ZN(new_n686));
  AND2_X1   g360(.A1(new_n664), .A2(new_n686), .ZN(G878));
  NAND2_X1  g361(.A1(G54), .A2(new_n600), .ZN(new_n690));
  NAND2_X1  g362(.A1(G42), .A2(new_n282), .ZN(new_n692));
  AND2_X1   g363(.A1(new_n690), .A2(new_n692), .ZN(new_n694));
  NAND2_X1  g364(.A1(new_n602), .A2(new_n618), .ZN(new_n696));
  INV_X1    g365(.A(new_n696), .ZN(new_n697));
  NAND2_X1  g366(.A1(G52), .A2(new_n697), .ZN(new_n698));
  NAND2_X1  g367(.A1(G53), .A2(new_n619), .ZN(new_n700));
  AND2_X1   g368(.A1(new_n698), .A2(new_n700), .ZN(new_n702));
  NAND2_X1  g369(.A1(G24), .A2(G50), .ZN(new_n704));
  AND2_X1   g370(.A1(new_n572), .A2(new_n588), .ZN(new_n706));
  NAND2_X1  g371(.A1(new_n558), .A2(new_n706), .ZN(new_n708));
  NAND2_X1  g372(.A1(new_n588), .A2(new_n609), .ZN(new_n710));
  AND2_X1   g373(.A1(new_n614), .A2(new_n710), .ZN(new_n712));
  NAND2_X1  g374(.A1(new_n708), .A2(new_n712), .ZN(new_n714));
  INV_X1    g375(.A(new_n714), .ZN(new_n715));
  NAND2_X1  g376(.A1(new_n696), .A2(new_n715), .ZN(new_n716));
  NAND2_X1  g377(.A1(new_n697), .A2(new_n714), .ZN(new_n718));
  AND2_X1   g378(.A1(new_n716), .A2(new_n718), .ZN(new_n720));
  NAND2_X1  g379(.A1(G51), .A2(new_n720), .ZN(new_n722));
  AND2_X1   g380(.A1(new_n704), .A2(new_n722), .ZN(new_n724));
  AND2_X1   g381(.A1(new_n702), .A2(new_n724), .ZN(new_n726));
  AND2_X1   g382(.A1(new_n694), .A2(new_n726), .ZN(G879));
  NAND2_X1  g383(.A1(G54), .A2(new_n586), .ZN(new_n730));
  NAND2_X1  g384(.A1(G43), .A2(new_n282), .ZN(new_n732));
  AND2_X1   g385(.A1(new_n730), .A2(new_n732), .ZN(new_n734));
  NAND2_X1  g386(.A1(new_n588), .A2(new_n614), .ZN(new_n736));
  INV_X1    g387(.A(new_n736), .ZN(new_n737));
  NAND2_X1  g388(.A1(G52), .A2(new_n737), .ZN(new_n738));
  NAND2_X1  g389(.A1(G53), .A2(new_n615), .ZN(new_n740));
  AND2_X1   g390(.A1(new_n738), .A2(new_n740), .ZN(new_n742));
  NAND2_X1  g391(.A1(G25), .A2(G50), .ZN(new_n744));
  NAND2_X1  g392(.A1(new_n574), .A2(new_n608), .ZN(new_n746));
  INV_X1    g393(.A(new_n746), .ZN(new_n747));
  NAND2_X1  g394(.A1(new_n736), .A2(new_n747), .ZN(new_n748));
  NAND2_X1  g395(.A1(new_n737), .A2(new_n746), .ZN(new_n750));
  AND2_X1   g396(.A1(new_n748), .A2(new_n750), .ZN(new_n752));
  NAND2_X1  g397(.A1(G51), .A2(new_n752), .ZN(new_n754));
  AND2_X1   g398(.A1(new_n744), .A2(new_n754), .ZN(new_n756));
  AND2_X1   g399(.A1(new_n742), .A2(new_n756), .ZN(new_n758));
  AND2_X1   g400(.A1(new_n734), .A2(new_n758), .ZN(G880));
endmodule


