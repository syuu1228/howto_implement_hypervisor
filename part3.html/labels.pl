# LaTeX2HTML 2012 (1.2)
# Associate labels original text with physical files.


$key = q/tab2/;
$external_labels{$key} = "$URL/" . q|node7.html|; 
$noresave{$key} = "$nosave";

$key = q/fig1/;
$external_labels{$key} = "$URL/" . q|node6.html|; 
$noresave{$key} = "$nosave";

$key = q/tab1/;
$external_labels{$key} = "$URL/" . q|node6.html|; 
$noresave{$key} = "$nosave";

$key = q/tab4/;
$external_labels{$key} = "$URL/" . q|node10.html|; 
$noresave{$key} = "$nosave";

$key = q/tab3/;
$external_labels{$key} = "$URL/" . q|node8.html|; 
$noresave{$key} = "$nosave";

1;


# LaTeX2HTML 2012 (1.2)
# labels from external_latex_labels array.


$key = q/tab2/;
$external_latex_labels{$key} = q|2|; 
$noresave{$key} = "$nosave";

$key = q/fig1/;
$external_latex_labels{$key} = q|1|; 
$noresave{$key} = "$nosave";

$key = q/tab1/;
$external_latex_labels{$key} = q|1|; 
$noresave{$key} = "$nosave";

$key = q/tab4/;
$external_latex_labels{$key} = q|4|; 
$noresave{$key} = "$nosave";

$key = q/tab3/;
$external_latex_labels{$key} = q|3|; 
$noresave{$key} = "$nosave";

1;

