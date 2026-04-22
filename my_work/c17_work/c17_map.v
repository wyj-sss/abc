// Benchmark "c17_work/c17" written by ABC on Wed Mar 18 18:49:45 2026

module \c17_work/c17  ( 
    G1, G3, G2, G4, G5,
    G16, G17  );
  input  G1, G3, G2, G4, G5;
  output G16, G17;
  wire new_n8, new_n9, new_n10, new_n12, new_n13;
  NAND2_X1  g0(.A1(G1), .A2(G3), .ZN(new_n8));
  NAND2_X1  g1(.A1(G3), .A2(G4), .ZN(new_n9));
  NAND2_X1  g2(.A1(new_n9), .A2(G2), .ZN(new_n10));
  NAND2_X1  g3(.A1(new_n10), .A2(new_n8), .ZN(G16));
  INV_X1    g4(.A(G2), .ZN(new_n12));
  INV_X1    g5(.A(G5), .ZN(new_n13));
  AOI22_X1  g6(.A1(new_n12), .A2(new_n13), .B1(G3), .B2(G4), .ZN(G17));
endmodule


