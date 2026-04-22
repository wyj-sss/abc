// Benchmark "c17" written by ABC on Thu Mar 19 15:21:17 2026

module c17 ( 
    G1, G3, G2, G4, G5,
    G16, G17  );
  input  G1, G3, G2, G4, G5;
  output G16, G17;
  wire new_n8, new_n9, new_n10, new_n12;
  NAND2_X1  g0(.A1(G1), .A2(G3), .ZN(new_n8));
  NAND2_X1  g1(.A1(G3), .A2(G4), .ZN(new_n9));
  NAND2_X1  g2(.A1(new_n9), .A2(G2), .ZN(new_n10));
  NAND2_X1  g3(.A1(new_n10), .A2(new_n8), .ZN(G16));
  NAND2_X1  g4(.A1(new_n9), .A2(G5), .ZN(new_n12));
  NAND2_X1  g5(.A1(new_n10), .A2(new_n12), .ZN(G17));
endmodule


