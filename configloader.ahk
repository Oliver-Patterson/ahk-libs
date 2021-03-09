#Include <json>
#Include <functionsahkshouldfuckinghave>
class configLoader {
	__New(file, default := "") {
		this.file := file
		if (!IsObject(default) && default)
			throw Exception("Invalid default object", -1)

		this.default := default
		if !FileExist(this.file)
			this.fixfile()

		this.loadfile()
		if !isObject(this.data) {
			this.fixfile()
		}
	}

	fixfile() {
		debug.print("Fixing", {label: this.file})

		file := FileOpen(this.file, "w")
		file.Write(JSON.dump(IsObject(this.default) ? this.default : {}))
		file.close()
		this.loadfile()
	}

	loadfile() {
		data := JSON.Load(fileopen(this.file, "r").read())
		this.data := this.default ? ObjectMerge(data, this.default) : data
	}

	save() {
		debug.print("Saving", {label: this.file})

		file := FileOpen(this.file, "w")
		file.write(JSON.Dump(this.data))
		file.close()
	}
}