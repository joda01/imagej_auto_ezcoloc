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
	filename = input + File.separator + file;
	run("Bio-Formats Importer", "open=["+filename+"] autoscale color_mode=Grayscale rois_import=[ROI manager] specify_range split_channels view=Hyperstack stack_order=XYCZT series_1 c_begin_1=1 c_end_1=2 c_step_1=1"); 

	list1 = getList("image.titles");

	if (list1.length==0){
    	print("No image windows are open");
	}
  	else {
     print("Image windows:");
     for (i=0; i<list1.length; i++){
        selectWindow(list1[i]);
        run("Enhance Contrast...", "saturated=0.3 normalize");
		run("Subtract Background...", "rolling=4");
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
	selectWindow(list1[0]);
	roiManager("Measure");
	saveAs("Results", output+File.separator + file+"_1.csv");

	run("Clear Results");

	// Measure picture 2
	selectWindow(list1[1]);
	roiManager("Measure");
	saveAs("Results", output+File.separator + file+"_2.csv");

	cleanUp();
}


///
/// \brief Closes all open windows
///
function cleanUp() {
	
	list = getList("window.titles");
     for (i=0; i<list.length; i++){
     winame = list[i];
      selectWindow(winame);
     run("Close");
     }
     close("*");
}
