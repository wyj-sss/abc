// Benchmark "c880_work/c880" written by ABC on Fri Mar 20 09:25:54 2026

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
  wire new_n89, new_n90, new_n91, new_n92, new_n95, new_n97, new_n98,
    new_n106, new_n107, new_n109, new_n112, new_n113, new_n114, new_n115,
    new_n116, new_n117, new_n118, new_n119, new_n121, new_n122, new_n123,
    new_n124, new_n125, new_n126, new_n127, new_n128, new_n130, new_n131,
    new_n132, new_n133, new_n134, new_n135, new_n136, new_n137, new_n138,
    new_n139, new_n140, new_n141, new_n142, new_n143, new_n144, new_n145,
    new_n146, new_n147, new_n148, new_n149, new_n150, new_n151, new_n152,
    new_n153, new_n154, new_n155, new_n156, new_n157, new_n158, new_n159,
    new_n160, new_n161, new_n162, new_n164, new_n165, new_n166, new_n167,
    new_n168, new_n169, new_n170, new_n171, new_n172, new_n173, new_n174,
    new_n175, new_n176, new_n177, new_n178, new_n179, new_n180, new_n181,
    new_n182, new_n183, new_n184, new_n185, new_n186, new_n187, new_n188,
    new_n189, new_n190, new_n191, new_n192, new_n193, new_n194, new_n195,
    new_n196, new_n198, new_n199, new_n200, new_n201, new_n202, new_n203,
    new_n204, new_n205, new_n206, new_n207, new_n208, new_n209, new_n210,
    new_n211, new_n213, new_n214, new_n215, new_n216, new_n217, new_n218,
    new_n219, new_n220, new_n221, new_n222, new_n223, new_n225, new_n226,
    new_n227, new_n228, new_n229, new_n230, new_n231, new_n232, new_n233,
    new_n234, new_n235, new_n236, new_n237, new_n238, new_n239, new_n240,
    new_n241, new_n242, new_n243, new_n244, new_n245, new_n246, new_n247,
    new_n248, new_n249, new_n250, new_n251, new_n252, new_n253, new_n254,
    new_n255, new_n256, new_n257, new_n258, new_n260, new_n261, new_n262,
    new_n263, new_n264, new_n265, new_n266, new_n268, new_n269, new_n270,
    new_n271, new_n272, new_n273, new_n274, new_n275, new_n277, new_n278,
    new_n279, new_n280, new_n281, new_n282, new_n283, new_n284, new_n285,
    new_n286, new_n287, new_n289, new_n290, new_n291, new_n292, new_n293,
    new_n294, new_n295, new_n296, new_n297;
  NAND3_X1  g000(.A1(G8), .A2(G16), .A3(G6), .ZN(G855));
  NAND3_X1  g001(.A1(G6), .A2(G17), .A3(G7), .ZN(G856));
  INV_X1    g002(.A(G8), .ZN(new_n89));
  INV_X1    g003(.A(G6), .ZN(new_n90));
  INV_X1    g004(.A(G7), .ZN(new_n91));
  NOR3_X1   g005(.A1(new_n89), .A2(new_n90), .A3(new_n91), .ZN(new_n92));
  INV_X1    g006(.A(new_n92), .ZN(G857));
  NAND2_X1  g007(.A1(G18), .A2(G19), .ZN(G858));
  AND2_X1   g008(.A1(G2), .A2(G1), .ZN(new_n95));
  NAND3_X1  g009(.A1(new_n95), .A2(G4), .A3(G3), .ZN(G859));
  AND2_X1   g010(.A1(G1), .A2(G5), .ZN(new_n97));
  NAND3_X1  g011(.A1(new_n97), .A2(G4), .A3(G3), .ZN(new_n98));
  NOR2_X1   g012(.A1(new_n92), .A2(new_n98), .ZN(G860));
  AND3_X1   g013(.A1(G16), .A2(G17), .A3(G11), .ZN(G861));
  AND3_X1   g014(.A1(G17), .A2(G7), .A3(G11), .ZN(G862));
  AND3_X1   g015(.A1(G8), .A2(G7), .A3(G11), .ZN(G863));
  OAI21_X1  g016(.A(G23), .B1(G20), .B2(G21), .ZN(G864));
  NOR2_X1   g017(.A1(G857), .A2(new_n98), .ZN(G865));
  NAND3_X1  g018(.A1(G1), .A2(G5), .A3(G9), .ZN(G866));
  NAND3_X1  g019(.A1(new_n95), .A2(G3), .A3(G10), .ZN(new_n106));
  NAND2_X1  g020(.A1(G6), .A2(G12), .ZN(new_n107));
  OR2_X1    g021(.A1(new_n106), .A2(new_n107), .ZN(G867));
  NAND3_X1  g022(.A1(G11), .A2(G12), .A3(G15), .ZN(new_n109));
  OR2_X1    g023(.A1(new_n106), .A2(new_n109), .ZN(G868));
  OAI21_X1  g024(.A(G22), .B1(G20), .B2(G21), .ZN(G869));
  XNOR2_X1  g025(.A(G24), .B(G25), .ZN(new_n112));
  XNOR2_X1  g026(.A(G26), .B(G27), .ZN(new_n113));
  XNOR2_X1  g027(.A(new_n112), .B(new_n113), .ZN(new_n114));
  XNOR2_X1  g028(.A(new_n114), .B(G32), .ZN(new_n115));
  XNOR2_X1  g029(.A(G28), .B(G29), .ZN(new_n116));
  XNOR2_X1  g030(.A(G30), .B(G31), .ZN(new_n117));
  XNOR2_X1  g031(.A(new_n116), .B(new_n117), .ZN(new_n118));
  XNOR2_X1  g032(.A(new_n118), .B(G33), .ZN(new_n119));
  XNOR2_X1  g033(.A(new_n115), .B(new_n119), .ZN(G870));
  XNOR2_X1  g034(.A(G41), .B(G42), .ZN(new_n121));
  XNOR2_X1  g035(.A(G43), .B(G44), .ZN(new_n122));
  XNOR2_X1  g036(.A(new_n121), .B(new_n122), .ZN(new_n123));
  XNOR2_X1  g037(.A(new_n123), .B(G32), .ZN(new_n124));
  XNOR2_X1  g038(.A(G45), .B(G46), .ZN(new_n125));
  XNOR2_X1  g039(.A(G47), .B(G48), .ZN(new_n126));
  XNOR2_X1  g040(.A(new_n125), .B(new_n126), .ZN(new_n127));
  XNOR2_X1  g041(.A(new_n127), .B(G49), .ZN(new_n128));
  XNOR2_X1  g042(.A(new_n124), .B(new_n128), .ZN(G871));
  INV_X1    g043(.A(G48), .ZN(new_n130));
  INV_X1    g044(.A(G14), .ZN(new_n131));
  NAND4_X1  g045(.A1(G8), .A2(G11), .A3(G12), .A4(G13), .ZN(new_n132));
  NOR3_X1   g046(.A1(new_n106), .A2(new_n132), .A3(new_n131), .ZN(new_n133));
  INV_X1    g047(.A(new_n133), .ZN(new_n134));
  NOR2_X1   g048(.A1(new_n134), .A2(new_n130), .ZN(new_n135));
  AND2_X1   g049(.A1(G55), .A2(G59), .ZN(new_n136));
  INV_X1    g050(.A(G10), .ZN(new_n137));
  NAND3_X1  g051(.A1(G16), .A2(G6), .A3(G17), .ZN(new_n138));
  NOR4_X1   g052(.A1(G866), .A2(new_n138), .A3(new_n137), .A4(G60), .ZN(new_n139));
  INV_X1    g053(.A(G39), .ZN(new_n140));
  NAND2_X1  g054(.A1(G11), .A2(G40), .ZN(new_n141));
  NAND4_X1  g055(.A1(new_n97), .A2(G4), .A3(G9), .A4(new_n141), .ZN(new_n142));
  AOI21_X1  g056(.A(new_n140), .B1(new_n142), .B2(G1), .ZN(new_n143));
  INV_X1    g057(.A(G31), .ZN(new_n144));
  AND4_X1   g058(.A1(G1), .A2(G5), .A3(G9), .A4(G40), .ZN(new_n145));
  INV_X1    g059(.A(G4), .ZN(new_n146));
  NAND2_X1  g060(.A1(new_n89), .A2(new_n146), .ZN(new_n147));
  NAND2_X1  g061(.A1(G8), .A2(G4), .ZN(new_n148));
  NAND4_X1  g062(.A1(new_n145), .A2(G11), .A3(new_n147), .A4(new_n148), .ZN(new_n149));
  NAND3_X1  g063(.A1(G8), .A2(G16), .A3(G11), .ZN(new_n150));
  NAND4_X1  g064(.A1(new_n95), .A2(new_n150), .A3(G4), .A4(G9), .ZN(new_n151));
  AOI21_X1  g065(.A(new_n144), .B1(new_n149), .B2(new_n151), .ZN(new_n152));
  NOR3_X1   g066(.A1(new_n152), .A2(new_n139), .A3(new_n143), .ZN(new_n153));
  INV_X1    g067(.A(new_n153), .ZN(new_n154));
  AOI211_X1 g068(.A(new_n135), .B(new_n136), .C1(new_n154), .C2(G54), .ZN(new_n155));
  NOR2_X1   g069(.A1(new_n153), .A2(new_n130), .ZN(new_n156));
  XNOR2_X1  g070(.A(new_n153), .B(G48), .ZN(new_n157));
  AOI22_X1  g071(.A1(new_n157), .A2(G52), .B1(G53), .B2(new_n156), .ZN(new_n158));
  NAND2_X1  g072(.A1(G30), .A2(G50), .ZN(new_n159));
  INV_X1    g073(.A(G58), .ZN(new_n160));
  XNOR2_X1  g074(.A(new_n157), .B(new_n160), .ZN(new_n161));
  NAND2_X1  g075(.A1(new_n161), .A2(G51), .ZN(new_n162));
  AND4_X1   g076(.A1(new_n155), .A2(new_n162), .A3(new_n158), .A4(new_n159), .ZN(G872));
  INV_X1    g077(.A(new_n139), .ZN(new_n164));
  NAND2_X1  g078(.A1(new_n142), .A2(G1), .ZN(new_n165));
  NAND3_X1  g079(.A1(new_n97), .A2(G9), .A3(G40), .ZN(new_n166));
  NAND3_X1  g080(.A1(new_n147), .A2(G11), .A3(new_n148), .ZN(new_n167));
  OAI21_X1  g081(.A(new_n151), .B1(new_n167), .B2(new_n166), .ZN(new_n168));
  AOI22_X1  g082(.A1(new_n168), .A2(G28), .B1(new_n165), .B2(G35), .ZN(new_n169));
  NAND2_X1  g083(.A1(new_n169), .A2(new_n164), .ZN(new_n170));
  AOI22_X1  g084(.A1(new_n170), .A2(G54), .B1(G45), .B2(new_n133), .ZN(new_n171));
  NAND2_X1  g085(.A1(new_n170), .A2(G45), .ZN(new_n172));
  INV_X1    g086(.A(new_n172), .ZN(new_n173));
  NOR2_X1   g087(.A1(new_n170), .A2(G45), .ZN(new_n174));
  NOR2_X1   g088(.A1(new_n173), .A2(new_n174), .ZN(new_n175));
  AOI22_X1  g089(.A1(new_n175), .A2(G52), .B1(G53), .B2(new_n173), .ZN(new_n176));
  NAND2_X1  g090(.A1(G27), .A2(G50), .ZN(new_n177));
  AOI21_X1  g091(.A(new_n160), .B1(new_n153), .B2(new_n130), .ZN(new_n178));
  INV_X1    g092(.A(G47), .ZN(new_n179));
  NAND2_X1  g093(.A1(new_n165), .A2(G37), .ZN(new_n180));
  NAND2_X1  g094(.A1(new_n168), .A2(G30), .ZN(new_n181));
  NAND4_X1  g095(.A1(new_n181), .A2(new_n179), .A3(new_n164), .A4(new_n180), .ZN(new_n182));
  INV_X1    g096(.A(G46), .ZN(new_n183));
  NAND2_X1  g097(.A1(new_n165), .A2(G36), .ZN(new_n184));
  NAND2_X1  g098(.A1(new_n168), .A2(G29), .ZN(new_n185));
  NAND4_X1  g099(.A1(new_n185), .A2(new_n183), .A3(new_n164), .A4(new_n184), .ZN(new_n186));
  AND2_X1   g100(.A1(new_n182), .A2(new_n186), .ZN(new_n187));
  OAI21_X1  g101(.A(new_n187), .B1(new_n178), .B2(new_n156), .ZN(new_n188));
  AOI22_X1  g102(.A1(new_n168), .A2(G30), .B1(new_n165), .B2(G37), .ZN(new_n189));
  AOI21_X1  g103(.A(new_n179), .B1(new_n189), .B2(new_n164), .ZN(new_n190));
  AOI22_X1  g104(.A1(new_n168), .A2(G29), .B1(new_n165), .B2(G36), .ZN(new_n191));
  AOI21_X1  g105(.A(new_n183), .B1(new_n191), .B2(new_n164), .ZN(new_n192));
  AOI21_X1  g106(.A(new_n192), .B1(new_n186), .B2(new_n190), .ZN(new_n193));
  NAND2_X1  g107(.A1(new_n188), .A2(new_n193), .ZN(new_n194));
  XOR2_X1   g108(.A(new_n194), .B(new_n175), .Z(new_n195));
  NAND2_X1  g109(.A1(new_n195), .A2(G51), .ZN(new_n196));
  AND4_X1   g110(.A1(new_n171), .A2(new_n196), .A3(new_n176), .A4(new_n177), .ZN(G873));
  NAND2_X1  g111(.A1(new_n191), .A2(new_n164), .ZN(new_n198));
  NOR2_X1   g112(.A1(new_n134), .A2(new_n183), .ZN(new_n199));
  AND2_X1   g113(.A1(G55), .A2(G56), .ZN(new_n200));
  AOI211_X1 g114(.A(new_n200), .B(new_n199), .C1(new_n198), .C2(G54), .ZN(new_n201));
  INV_X1    g115(.A(new_n186), .ZN(new_n202));
  NOR2_X1   g116(.A1(new_n202), .A2(new_n192), .ZN(new_n203));
  AOI22_X1  g117(.A1(new_n203), .A2(G52), .B1(G53), .B2(new_n192), .ZN(new_n204));
  NAND2_X1  g118(.A1(G28), .A2(G50), .ZN(new_n205));
  OAI21_X1  g119(.A(new_n182), .B1(new_n154), .B2(G48), .ZN(new_n206));
  AOI21_X1  g120(.A(new_n190), .B1(new_n156), .B2(new_n182), .ZN(new_n207));
  OAI21_X1  g121(.A(new_n207), .B1(new_n160), .B2(new_n206), .ZN(new_n208));
  OR2_X1    g122(.A1(new_n208), .A2(new_n203), .ZN(new_n209));
  NAND2_X1  g123(.A1(new_n208), .A2(new_n203), .ZN(new_n210));
  NAND3_X1  g124(.A1(new_n209), .A2(G51), .A3(new_n210), .ZN(new_n211));
  AND4_X1   g125(.A1(new_n201), .A2(new_n211), .A3(new_n204), .A4(new_n205), .ZN(G874));
  NAND2_X1  g126(.A1(new_n189), .A2(new_n164), .ZN(new_n213));
  NOR2_X1   g127(.A1(new_n134), .A2(new_n179), .ZN(new_n214));
  AND2_X1   g128(.A1(G55), .A2(G57), .ZN(new_n215));
  AOI211_X1 g129(.A(new_n215), .B(new_n214), .C1(new_n213), .C2(G54), .ZN(new_n216));
  INV_X1    g130(.A(new_n182), .ZN(new_n217));
  NOR2_X1   g131(.A1(new_n217), .A2(new_n190), .ZN(new_n218));
  AOI22_X1  g132(.A1(new_n218), .A2(G52), .B1(G53), .B2(new_n190), .ZN(new_n219));
  NAND2_X1  g133(.A1(G29), .A2(G50), .ZN(new_n220));
  NOR2_X1   g134(.A1(new_n178), .A2(new_n156), .ZN(new_n221));
  XNOR2_X1  g135(.A(new_n221), .B(new_n218), .ZN(new_n222));
  NAND2_X1  g136(.A1(new_n222), .A2(G51), .ZN(new_n223));
  AND4_X1   g137(.A1(new_n216), .A2(new_n223), .A3(new_n219), .A4(new_n220), .ZN(G875));
  AOI22_X1  g138(.A1(new_n168), .A2(G24), .B1(G2), .B2(G34), .ZN(new_n225));
  AOI211_X1 g139(.A(new_n137), .B(G866), .C1(G11), .C2(G40), .ZN(new_n226));
  NOR4_X1   g140(.A1(G866), .A2(new_n138), .A3(new_n146), .A4(G60), .ZN(new_n227));
  AOI21_X1  g141(.A(new_n227), .B1(new_n226), .B2(G35), .ZN(new_n228));
  NAND2_X1  g142(.A1(new_n225), .A2(new_n228), .ZN(new_n229));
  NAND2_X1  g143(.A1(new_n229), .A2(G41), .ZN(new_n230));
  INV_X1    g144(.A(new_n230), .ZN(new_n231));
  AOI21_X1  g145(.A(new_n174), .B1(new_n188), .B2(new_n193), .ZN(new_n232));
  AOI22_X1  g146(.A1(new_n168), .A2(G27), .B1(G34), .B2(G38), .ZN(new_n233));
  AOI21_X1  g147(.A(new_n227), .B1(new_n226), .B2(G39), .ZN(new_n234));
  NAND2_X1  g148(.A1(new_n233), .A2(new_n234), .ZN(new_n235));
  NOR2_X1   g149(.A1(new_n235), .A2(G44), .ZN(new_n236));
  INV_X1    g150(.A(new_n236), .ZN(new_n237));
  AOI22_X1  g151(.A1(new_n168), .A2(G26), .B1(G4), .B2(G34), .ZN(new_n238));
  AOI21_X1  g152(.A(new_n227), .B1(new_n226), .B2(G37), .ZN(new_n239));
  NAND2_X1  g153(.A1(new_n238), .A2(new_n239), .ZN(new_n240));
  OR2_X1    g154(.A1(new_n240), .A2(G43), .ZN(new_n241));
  AOI22_X1  g155(.A1(new_n168), .A2(G25), .B1(G9), .B2(G34), .ZN(new_n242));
  AOI21_X1  g156(.A(new_n227), .B1(new_n226), .B2(G36), .ZN(new_n243));
  NAND2_X1  g157(.A1(new_n242), .A2(new_n243), .ZN(new_n244));
  OR2_X1    g158(.A1(new_n244), .A2(G42), .ZN(new_n245));
  AND2_X1   g159(.A1(new_n241), .A2(new_n245), .ZN(new_n246));
  OAI211_X1 g160(.A(new_n237), .B(new_n246), .C1(new_n232), .C2(new_n173), .ZN(new_n247));
  NAND2_X1  g161(.A1(new_n235), .A2(G44), .ZN(new_n248));
  INV_X1    g162(.A(new_n248), .ZN(new_n249));
  NAND2_X1  g163(.A1(new_n246), .A2(new_n249), .ZN(new_n250));
  NAND2_X1  g164(.A1(new_n240), .A2(G43), .ZN(new_n251));
  INV_X1    g165(.A(new_n251), .ZN(new_n252));
  NAND2_X1  g166(.A1(new_n244), .A2(G42), .ZN(new_n253));
  INV_X1    g167(.A(new_n253), .ZN(new_n254));
  AOI21_X1  g168(.A(new_n254), .B1(new_n245), .B2(new_n252), .ZN(new_n255));
  NAND3_X1  g169(.A1(new_n247), .A2(new_n250), .A3(new_n255), .ZN(new_n256));
  NOR2_X1   g170(.A1(new_n229), .A2(G41), .ZN(new_n257));
  INV_X1    g171(.A(new_n257), .ZN(new_n258));
  AOI21_X1  g172(.A(new_n231), .B1(new_n256), .B2(new_n258), .ZN(G876));
  AOI22_X1  g173(.A1(new_n235), .A2(G54), .B1(G44), .B2(new_n133), .ZN(new_n260));
  NOR2_X1   g174(.A1(new_n249), .A2(new_n236), .ZN(new_n261));
  AOI22_X1  g175(.A1(new_n261), .A2(G52), .B1(G53), .B2(new_n249), .ZN(new_n262));
  NAND2_X1  g176(.A1(G26), .A2(G50), .ZN(new_n263));
  NOR2_X1   g177(.A1(new_n232), .A2(new_n173), .ZN(new_n264));
  XNOR2_X1  g178(.A(new_n264), .B(new_n261), .ZN(new_n265));
  NAND2_X1  g179(.A1(new_n265), .A2(G51), .ZN(new_n266));
  AND4_X1   g180(.A1(new_n260), .A2(new_n266), .A3(new_n262), .A4(new_n263), .ZN(G877));
  AOI22_X1  g181(.A1(new_n229), .A2(G54), .B1(G41), .B2(new_n133), .ZN(new_n268));
  NOR2_X1   g182(.A1(new_n231), .A2(new_n257), .ZN(new_n269));
  AOI22_X1  g183(.A1(new_n269), .A2(G52), .B1(G53), .B2(new_n231), .ZN(new_n270));
  NAND2_X1  g184(.A1(G60), .A2(G50), .ZN(new_n271));
  INV_X1    g185(.A(new_n269), .ZN(new_n272));
  NAND4_X1  g186(.A1(new_n247), .A2(new_n250), .A3(new_n255), .A4(new_n272), .ZN(new_n273));
  NAND2_X1  g187(.A1(new_n256), .A2(new_n269), .ZN(new_n274));
  NAND3_X1  g188(.A1(new_n274), .A2(G51), .A3(new_n273), .ZN(new_n275));
  AND4_X1   g189(.A1(new_n268), .A2(new_n275), .A3(new_n270), .A4(new_n271), .ZN(G878));
  AOI22_X1  g190(.A1(new_n244), .A2(G54), .B1(G42), .B2(new_n133), .ZN(new_n277));
  NAND2_X1  g191(.A1(new_n245), .A2(new_n253), .ZN(new_n278));
  INV_X1    g192(.A(new_n278), .ZN(new_n279));
  AOI22_X1  g193(.A1(new_n279), .A2(G52), .B1(G53), .B2(new_n254), .ZN(new_n280));
  NAND2_X1  g194(.A1(G24), .A2(G50), .ZN(new_n281));
  NAND2_X1  g195(.A1(new_n237), .A2(new_n241), .ZN(new_n282));
  AOI21_X1  g196(.A(new_n252), .B1(new_n241), .B2(new_n249), .ZN(new_n283));
  OAI211_X1 g197(.A(new_n278), .B(new_n283), .C1(new_n264), .C2(new_n282), .ZN(new_n284));
  OAI21_X1  g198(.A(new_n283), .B1(new_n264), .B2(new_n282), .ZN(new_n285));
  NAND2_X1  g199(.A1(new_n285), .A2(new_n279), .ZN(new_n286));
  NAND3_X1  g200(.A1(new_n286), .A2(G51), .A3(new_n284), .ZN(new_n287));
  AND4_X1   g201(.A1(new_n277), .A2(new_n287), .A3(new_n280), .A4(new_n281), .ZN(G879));
  AOI22_X1  g202(.A1(new_n240), .A2(G54), .B1(G43), .B2(new_n133), .ZN(new_n289));
  NAND2_X1  g203(.A1(new_n241), .A2(new_n251), .ZN(new_n290));
  INV_X1    g204(.A(new_n290), .ZN(new_n291));
  AOI22_X1  g205(.A1(new_n291), .A2(G52), .B1(G53), .B2(new_n252), .ZN(new_n292));
  NAND2_X1  g206(.A1(G25), .A2(G50), .ZN(new_n293));
  OAI211_X1 g207(.A(new_n248), .B(new_n290), .C1(new_n264), .C2(new_n236), .ZN(new_n294));
  OAI21_X1  g208(.A(new_n248), .B1(new_n264), .B2(new_n236), .ZN(new_n295));
  NAND2_X1  g209(.A1(new_n295), .A2(new_n291), .ZN(new_n296));
  NAND3_X1  g210(.A1(new_n296), .A2(G51), .A3(new_n294), .ZN(new_n297));
  AND4_X1   g211(.A1(new_n289), .A2(new_n297), .A3(new_n292), .A4(new_n293), .ZN(G880));
endmodule


