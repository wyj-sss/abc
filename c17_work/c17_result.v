module C17 (\1GAT(0) ,
    \22GAT(10) ,
    \23GAT(9) ,
    \2GAT(1) ,
    \3GAT(2) ,
    \6GAT(3) ,
    \7GAT(4) );
 input \1GAT(0) ;
 output \22GAT(10) ;
 output \23GAT(9) ;
 input \2GAT(1) ;
 input \3GAT(2) ;
 input \6GAT(3) ;
 input \7GAT(4) ;

 wire new_n10;
 wire new_n12;
 wire new_n13;
 wire new_n8;
 wire new_n9;

 NAND2_X1 g0 (.A1(\1GAT(0) ),
    .A2(\3GAT(2) ),
    .ZN(new_n8));
 NAND2_X1 g1 (.A1(\3GAT(2) ),
    .A2(\6GAT(3) ),
    .ZN(new_n9));
 NAND2_X1 g2 (.A1(new_n9),
    .A2(\2GAT(1) ),
    .ZN(new_n10));
 NAND2_X1 g3 (.A1(new_n10),
    .A2(new_n8),
    .ZN(\22GAT(10) ));
 INV_X1 g4 (.A(\2GAT(1) ),
    .ZN(new_n12));
 INV_X1 g5 (.A(\7GAT(4) ),
    .ZN(new_n13));
 AOI22_X1 g6 (.A1(new_n12),
    .A2(new_n13),
    .B1(\3GAT(2) ),
    .B2(\6GAT(3) ),
    .ZN(\23GAT(9) ));
endmodule
