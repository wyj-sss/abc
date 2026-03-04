// Benchmark "c17_work/c17" written by ABC on Wed Feb  4 16:34:55 2026

module C17 ( 
    \1GAT(0) , \2GAT(1) , \3GAT(2) , \6GAT(3) , \7GAT(4) ,
    \22GAT(10) , \23GAT(9)   );
  input  \1GAT(0) , \2GAT(1) , \3GAT(2) , \6GAT(3) , \7GAT(4) ;
  output \22GAT(10) , \23GAT(9) ;
  wire new_n8, new_n9, new_n10, new_n12;
  NAND2_X1  g0(.A1(\1GAT(0) ), .A2(\3GAT(2) ), .ZN(new_n8));
  NAND2_X1  g1(.A1(\3GAT(2) ), .A2(\6GAT(3) ), .ZN(new_n9));
  NAND2_X1  g2(.A1(new_n9), .A2(\2GAT(1) ), .ZN(new_n10));
  NAND2_X1  g3(.A1(new_n10), .A2(new_n8), .ZN(\22GAT(10) ));
  NAND2_X1  g4(.A1(new_n9), .A2(\7GAT(4) ), .ZN(new_n12));
  NAND2_X1  g5(.A1(new_n10), .A2(new_n12), .ZN(\23GAT(9) ));
endmodule


