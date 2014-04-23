# LaTeX2HTML 2012 (1.2)
# Associate labels original text with physical files.


$key = q/tab1/;
$external_labels{$key} = "$URL/" . q|node3.html|; 
$noresave{$key} = "$nosave";

$key = q/cite_interrupt-routing/;
$external_labels{$key} = "$URL/" . q|node15.html|; 
$noresave{$key} = "$nosave";

$key = q/fig1/;
$external_labels{$key} = "$URL/" . q|node1.html|; 
$noresave{$key} = "$nosave";

1;


# LaTeX2HTML 2012 (1.2)
# labels from external_latex_labels array.


$key = q/_/;
$external_latex_labels{$key} = q|<|; 
$noresave{$key} = "$nosave";

$key = q/fig1/;
$external_latex_labels{$key} = q|1|; 
$noresave{$key} = "$nosave";

$key = q/tab1/;
$external_latex_labels{$key} = q|1|; 
$noresave{$key} = "$nosave";

1;

