///
/// \file  	auto_coloc.ijm
/// \author	Joachim Danmayr
/// \date	2020-08-02
/// \brief  Uses the EzColocalization plugin to calculate the
///			colocalzation for vsi images stored in a folder.
///
///         The result is stored to the output folder
///


/// Open dialog to choose input and output folder
#@ File (label = "Input directory", style = "directory") input
#@ File (label = "Output directory", style = "directory") output
#@ String (label = "File suffix", value = ".vsi") suffix

///
/// Seems to be the main :)
///
processFolder(input);

///
/// Look recursie for vsi files and process them
///
function processFolder(input) {
	list = getFileList(input);
	list = Array.sort(list);
	for (i = 0; i < list.length; i++) {
		if(File.isDirectory(input + File.separator + list[i]))
			processFolder(input + File.separator + list[i]);
		if(endsWith(list[i], suffix))
			processFile(input, output, list[i]);
	}

}

///
/// Just a stub function
///
function processFile(input, output, file) {
	print("Processing: " + input + File.separator + file);
	print("Saving to: " + output);
	openVsiFile(input, output, file);
}

///
/// Open a two channel VSI and runs the EzColoc algorithm on it
///
function openVsiFile(input, output, file){
	cleanUp();

	
	filename = input + File.separator + file;
	run("Bio-Formats Importer", "open=["+filename+"] autoscale color_mode=Grayscale rois_import=[ROI manager] specify_range split_channels view=Hyperstack stack_order=XYCZT series_1 c_begin_1=1 c_end_1=2 c_step_1=1"); 

	list1 = getList("image.titles");

	if (list1.length==0){
    	print("No image windows are open");
	}
  	else {
  		gfpIndex = 0;
  	 	cy3Index = 1;
  	 
     print("Image windows:");
     for (i=0; i<list1.length; i++){
     	
        selectWindow(list1[i]);
        
        if(true == endsWith(list1[i], "C=1")){
        	run("Enhance Contrast...", "saturated=0.3 normalize");
        	print("Enhace CY3 " + toString(i));
        	cy3Index = i;
        }else{
        	gfpIndex = i;
        	run("Enhance Contrast...", "saturated=0.1 normalize");
        }
		run("Subtract Background...", "rolling=4 sliding");
		run("Convolve...", "text1=[1 4 6 4 1\n4 16 24 16 4\n6 24 36 24 6\n4 16 24 16 4\n1 4 6 4 1] normalize");

		setAutoThreshold("Li dark");
		setOption("BlackBackground", true);
		run("Convert to Mask");
     }
  	}

	// Make the sum of both pictures to use this as Cell Identifier input | Add
  	imageCalculator("Max create", list1[0],list1[1]);
  	selectWindow("Result of "+list1[0]);
	run("Analyze Particles...", "clear add");
  	
	// Measure picture 1
	selectWindow(list1[gfpIndex]);
	roiManager("Measure");
	saveAs("Results", output+File.separator + file+"_gfp.csv");

	run("Clear Results");

	// Measure picture 2
	selectWindow(list1[cy3Index]);
	roiManager("Measure");
	saveAs("Results", output+File.separator + file+"_cy3.csv");

	cleanUp();

	calcMeasurement(output+File.separator + file+"_gfp.csv",output+File.separator + file+"_cy3.csv",output);
}


///
/// Calculates the Coloc coefficent
/// The result is a value in range from [0, 255]
/// 0 is no coloc 255 is maximum coloc.
///
function calcMeasurement(resultgfp, resultcy3, output){
	read1 = File.openAsString(resultgfp);
	read2 = File.openAsString(resultcy3);

	lines1 = split(read1, "\n");
	lines2 = split(read2, "\n");

	result = "ROI\t\t Area\t\t GFP\t\t CY3\t\t DIFF\n";

	for(i = 1; i<lines1.length; i++){
		 linegfp = split(lines1[i],",");
		 linecy3 = split(lines2[i],",");

		  a = parseFloat(linegfp[2]);
		  b = parseFloat(linecy3[2]);

		// Coloc algorithm
		 sub = abs(255 - abs(a - b));

	     result = result +linegfp[0] + "\t\t" + linegfp[1]+"\t\t"+linegfp[2]+"\t\t"+linecy3[2] + "\t\t"+toString(sub)+"\n";
	}

	File.saveString(result, output+File.separator + file+"_final.txt");

}

///
/// \brief Closes all open windows
///
function cleanUp() {
     roiManager("Delete");
     list = getList("window.titles");
     for (i=0; i<list.length; i++){
     winame = list[i];
      selectWindow(winame);
     run("Close");
     }
     close("*");
}
